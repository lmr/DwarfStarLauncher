import Foundation
import SwiftUI
import Network
import HuggingFaceDownloader

@Observable
final class ServerManager {
    var status: ServerStatus = .stopped
    var config: ServerConfig = ServerConfig()
    private(set) var logLines: [LogLine] = []
    let statusMonitor: StatusMonitor
    let configStore: ConfigStore
    private let serverBinaryResolver: ((ServerConfig) -> URL?)?

    /// AppDelegate connects this to the shared inline error banner.
    var onError: ((String) -> Void)?

    private var process: Process?
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?
    private var stopTimeoutTask: Task<Void, Never>?
    private var restartTask: Task<Void, Never>?
    private var readinessProbeTimer: Timer?
    private var readinessConnection: NWConnection?
    private var readinessAttempts = 0
    private var isStopping = false

    /// Maximum number of log lines retained in memory. Prevents an unbounded
    /// `logLines` array from leaking memory on long-running servers.
    private static let logLineLimit = 10_000

    init(
        statusMonitor: StatusMonitor,
        configStore: ConfigStore = ConfigStore(),
        serverBinaryResolver: ((ServerConfig) -> URL?)? = nil
    ) {
        self.statusMonitor = statusMonitor
        self.configStore = configStore
        self.serverBinaryResolver = serverBinaryResolver
        loadConfig()
    }

    /// Appends a log line and trims the oldest entries once the cap is exceeded.
    /// Internal (not private) so tests can exercise the cap without spawning a process.
    func appendLogLine(_ line: LogLine) {
        logLines.append(line)
        if logLines.count > Self.logLineLimit {
            logLines.removeFirst(logLines.count - Self.logLineLimit)
        }
    }

    func loadConfig() {
        if let decoded = configStore.load(ServerConfig.self) {
            config = decoded
        }
    }

    func spawn(config: ServerConfig) {
        guard process == nil else { return }
        restartTask?.cancel()
        restartTask = nil

        guard let executableURL = resolveServerBinary(for: config) else {
            let message = "Could not find ds4-server. Import a DS4 build, place an executable at \(PathResolver.serverBinary.path), or set a custom binary path/on PATH."
            reportLaunchError(message)
            return
        }

        var launchConfig = config
        if launchConfig.enableMtp {
            let mtpPath = (launchConfig.mtpModelPath as NSString).expandingTildeInPath
            if !FileManager.default.fileExists(atPath: mtpPath) {
                let warning = "Warning: MTP model not found at \(mtpPath); starting without MTP."
                appendLogLine(LogLine(timestamp: Date(), text: warning, level: .warning))
                launchConfig.enableMtp = false
            }
        }

        if launchConfig.enableVision {
            guard let rawVisionPath = launchConfig.visionEncoderPath else {
                reportLaunchError(
                    "Vision is enabled but no vision encoder is selected. " +
                    "Choose a valid DeepSeek/GLM vision encoder GGUF in Settings."
                )
                return
            }
            let trimmedVisionPath = rawVisionPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedVisionPath.isEmpty else {
                reportLaunchError(
                    "Vision is enabled but no vision encoder is selected. " +
                    "Choose a valid DeepSeek/GLM vision encoder GGUF in Settings."
                )
                return
            }

            let visionPath = (trimmedVisionPath as NSString).expandingTildeInPath
            guard FileManager.default.isReadableFile(atPath: visionPath) else {
                reportLaunchError(
                    "Vision encoder not found or unreadable at \(visionPath). " +
                    "Choose a valid DeepSeek/GLM vision encoder GGUF in Settings."
                )
                return
            }
            // NSOpenPanel stores absolute paths, but normalize manually
            // entered `~` paths before handing them to Process.
            launchConfig.visionEncoderPath = visionPath
        } else {
            // Keep a disabled path in the persisted config so re-enabling the
            // feature does not require selecting the encoder again.
            launchConfig.visionEncoderPath = nil
        }

        self.config = config
        statusMonitor.maxContext = config.contextSize
        statusMonitor.startTimer()
        status = .starting
        isStopping = false
        readinessAttempts = 0

        let proc = Process()
        proc.executableURL = executableURL
        let procArgs = launchConfig.buildArguments()
        proc.arguments = procArgs
        proc.currentDirectoryURL = PathResolver.dataRoot
        let processCmdLine = "\(executableURL.lastPathComponent) \(procArgs.joined(separator: " "))"
        appendLogLine(LogLine(timestamp: Date(), text: processCmdLine, level: .info))

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe
        stdoutHandle = stdoutPipe.fileHandleForReading
        stderrHandle = stderrPipe.fileHandleForReading

        installReadabilityHandler(on: stdoutHandle)
        installReadabilityHandler(on: stderrHandle)

        proc.terminationHandler = { [weak self] terminatedProcess in
            DispatchQueue.main.async {
                self?.handleTermination(of: terminatedProcess)
            }
        }

        do {
            try proc.run()
            process = proc
            startReadinessProbe(for: config)
        } catch {
            clearProcessIO()
            statusMonitor.stopTimer()
            process = nil
            reportLaunchError("Failed to launch ds4-server: \(error.localizedDescription)")
        }
    }

    func stop() {
        stop(cancelRestart: true)
    }

    private func stop(cancelRestart: Bool) {
        guard let proc = process else {
            if cancelRestart {
                restartTask?.cancel()
                restartTask = nil
            }
            statusMonitor.stopTimer()
            stopReadinessProbe()
            return
        }

        if cancelRestart {
            restartTask?.cancel()
            restartTask = nil
        }
        stopTimeoutTask?.cancel()
        stopTimeoutTask = nil
        isStopping = true
        statusMonitor.stopTimer()
        stopReadinessProbe()
        proc.terminate()

        let pid = proc.processIdentifier
        let processForTimeout = proc
        stopTimeoutTask = Task { @MainActor [weak self, processForTimeout] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            guard let self, self.process === processForTimeout, processForTimeout.isRunning else { return }
            kill(pid, SIGKILL)
        }
    }

    /// Used during application termination. The wait is deliberately confined
    /// to this synchronous shutdown path; normal Stop never blocks the UI.
    func stopSynchronously() {
        stopTimeoutTask?.cancel()
        stopTimeoutTask = nil
        restartTask?.cancel()
        restartTask = nil
        statusMonitor.stopTimer()
        stopReadinessProbe()

        guard let proc = process else {
            clearProcessIO()
            return
        }

        isStopping = true
        proc.terminate()
        let deadline = DispatchTime.now() + .seconds(5)
        while proc.isRunning && DispatchTime.now() < deadline {
            usleep(50_000)
        }
        if proc.isRunning {
            kill(proc.processIdentifier, SIGKILL)
        }
        clearProcessIO()
        process = nil
        isStopping = false
    }

    func restart() {
        let currentConfig = config
        restartTask?.cancel()
        restartTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // Keep the task reference so a user Stop can cancel a pending
            // restart, while avoiding self-cancellation here.
            self.stop(cancelRestart: false)
            // Poll only the main-actor-owned process reference. This handles a
            // slow graceful shutdown without racing a new spawn against it.
            for _ in 0..<100 {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled else { return }
                if self.process == nil {
                    try? await Task.sleep(for: .milliseconds(100))
                    guard !Task.isCancelled else { return }
                    self.restartTask = nil
                    self.spawn(config: currentConfig)
                    return
                }
            }
            self.reportLaunchError("Restart timed out while waiting for ds4-server to exit.")
        }
    }

    func clearLogs() {
        logLines.removeAll()
    }

    // MARK: - Process setup and output

    private func resolveServerBinary(for config: ServerConfig) -> URL? {
        if let serverBinaryResolver {
            return serverBinaryResolver(config)
        }
        let fm = FileManager.default
        if let customPath = config.serverBinaryPath, !customPath.isEmpty {
            let customURL = URL(fileURLWithPath: (customPath as NSString).expandingTildeInPath)
            if fm.isExecutableFile(atPath: customURL.path) { return customURL }
        }

        if fm.isExecutableFile(atPath: PathResolver.serverBinary.path) {
            return PathResolver.serverBinary
        }

        let pathEntries = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        for entry in pathEntries {
            let candidate = URL(fileURLWithPath: entry).appendingPathComponent("ds4-server")
            if fm.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    private func installReadabilityHandler(on handle: FileHandle?) {
        handle?.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
            DispatchQueue.main.async {
                for line in lines {
                    self?.processLogLine(line)
                }
            }
        }
    }

    private func processLogLine(_ line: String) {
        appendLogLine(LogLine(timestamp: Date(), text: line, level: classify(line)))
        statusMonitor.parse(line)

        if process != nil && line.localizedCaseInsensitiveContains("listening on http") {
            status = .running
            stopReadinessProbe()
        }
        if line.localizedCaseInsensitiveContains("shutdown requested") {
            status = .stopped
        }
    }

    private func handleTermination(of terminatedProcess: Process) {
        guard process === terminatedProcess || process == nil else { return }
        stopTimeoutTask?.cancel()
        stopTimeoutTask = nil
        stopReadinessProbe()
        clearProcessIO()
        process = nil

        if isStopping || terminatedProcess.terminationStatus == 0 {
            status = .stopped
        } else {
            status = .error(exitCode: terminatedProcess.terminationStatus)
        }
        isStopping = false
    }

    private func clearProcessIO() {
        stdoutHandle?.readabilityHandler = nil
        stderrHandle?.readabilityHandler = nil
        try? stdoutHandle?.close()
        try? stderrHandle?.close()
        stdoutHandle = nil
        stderrHandle = nil
    }

    private func reportLaunchError(_ message: String) {
        status = .error(exitCode: 127)
        appendLogLine(LogLine(timestamp: Date(), text: message, level: .error))
        onError?(message)
    }

    // MARK: - Readiness probe

    private func startReadinessProbe(for config: ServerConfig) {
        stopReadinessProbe()
        let host = config.host == "0.0.0.0" || config.host == "::" ? "127.0.0.1" : config.host
        guard let port = NWEndpoint.Port(rawValue: UInt16(clamping: config.port)) else { return }

        readinessProbeTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, self.status == .starting, self.process != nil else { return }
            self.readinessAttempts += 1
            if self.readinessAttempts > 40 {
                self.stopReadinessProbe()
                return
            }
            guard self.readinessConnection == nil else { return }

            let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
            self.readinessConnection = connection
            connection.stateUpdateHandler = { [weak self, weak connection] state in
                guard let self else { return }
                if state == .ready {
                    DispatchQueue.main.async {
                        guard self.process != nil else { return }
                        self.status = .running
                        self.stopReadinessProbe()
                    }
                } else if case .failed = state {
                    connection?.cancel()
                    DispatchQueue.main.async {
                        if self.readinessConnection === connection {
                            self.readinessConnection = nil
                        }
                    }
                }
            }
            connection.start(queue: .main)
        }
        RunLoop.main.add(readinessProbeTimer!, forMode: .default)
    }

    private func stopReadinessProbe() {
        readinessProbeTimer?.invalidate()
        readinessProbeTimer = nil
        readinessConnection?.cancel()
        readinessConnection = nil
        readinessAttempts = 0
    }

    // MARK: - Log classification

    func classify(_ text: String) -> LogLine.LogLevel {
        if text.localizedCaseInsensitiveContains("t/s") { return .timing }
        if text.localizedCaseInsensitiveContains("gen=") { return .generation }
        if text.localizedCaseInsensitiveContains("prefill") { return .prefill }
        if text.localizedCaseInsensitiveContains("kv cache") { return .kvcache }
        if text.localizedCaseInsensitiveContains("tool calls") { return .tool }
        if text.localizedCaseInsensitiveContains("warning") { return .warning }
        if text.localizedCaseInsensitiveContains("failed") || text.localizedCaseInsensitiveContains("error") {
            return .error
        }
        return .info
    }
}
