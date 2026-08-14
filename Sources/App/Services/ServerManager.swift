import Foundation
import SwiftUI

@Observable
final class ServerManager: @unchecked Sendable {
    var status: ServerStatus = .stopped
    var config: ServerConfig = ServerConfig()
    private(set) var logLines: [LogLine] = []
    let statusMonitor: StatusMonitor

    private var process: Process?
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?

    /// Maximum number of log lines retained in memory. Prevents an unbounded
    /// `logLines` array from leaking memory on long-running servers.
    private static let logLineLimit = 10_000

    /// Appends a log line and trims the oldest entries once the cap is exceeded.
    /// Internal (not private) so tests can exercise the cap without spawning a process.
    func appendLogLine(_ line: LogLine) {
        logLines.append(line)
        if logLines.count > Self.logLineLimit {
            logLines.removeFirst(logLines.count - Self.logLineLimit)
        }
    }

    init(statusMonitor: StatusMonitor) {
        self.statusMonitor = statusMonitor
        loadConfig()
    }

    private func loadConfig() {
        let file = PathResolver.configFile
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        guard let data = try? Data(contentsOf: file) else { return }
        if let decoded = try? JSONDecoder().decode(ServerConfig.self, from: data) {
            config = decoded
        }
    }

    func spawn(config: ServerConfig) {
        guard process == nil else { return }

        self.config = config
        statusMonitor.maxContext = config.contextSize
        statusMonitor.startTimer()
        status = .starting

        let proc = Process()
        proc.executableURL = PathResolver.serverBinary
        let procArgs = config.buildArguments()
        proc.arguments = procArgs
        proc.currentDirectoryURL = PathResolver.dataRoot
        let processCmdLine = "\(PathResolver.serverBinary.lastPathComponent) \(procArgs.joined(separator: " "))"
        let logLine = LogLine(timestamp: Date(), text: processCmdLine, level: .info)
        self.appendLogLine(logLine)
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        stdoutHandle = stdoutPipe.fileHandleForReading
        stderrHandle = stderrPipe.fileHandleForReading

        stdoutHandle?.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self = self, !data.isEmpty else { return }
            let lines = String(data: data, encoding: .utf8)?
                .components(separatedBy: .newlines)
                .filter { !$0.isEmpty } ?? []
            DispatchQueue.main.async {
                for line in lines {
                    let logLine = LogLine(timestamp: Date(), text: line, level: self.classify(line))
                    self.appendLogLine(logLine)
                    self.statusMonitor.parse(line)

                    if line.contains("shutdown requested") {
                        self.status = .stopped
                    }
                }
            }
        }

        stderrHandle?.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self = self, !data.isEmpty else { return }
            let lines = String(data: data, encoding: .utf8)?
                .components(separatedBy: .newlines)
                .filter { !$0.isEmpty } ?? []
            DispatchQueue.main.async {
                for line in lines {
                    let logLine = LogLine(timestamp: Date(), text: line, level: self.classify(line))
                    self.appendLogLine(logLine)
                    self.statusMonitor.parse(line)

                    if line.contains("listening on http") {
                        self.status = .running
                    }

                    if line.contains("shutdown requested") {
                        self.status = .stopped
                    }
                }
            }
        }

        proc.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if proc.terminationStatus == 0 {
                    self.status = .stopped
                } else {
                    self.status = .error(exitCode: proc.terminationStatus)
                }
                self.process = nil
                self.stdoutHandle = nil
                self.stderrHandle = nil
            }
        }

        do {
            try proc.run()
            process = proc
        } catch {
            status = .error(exitCode: -1)
            let logLine = LogLine(timestamp: Date(), text: "Failed to launch: \(error.localizedDescription)", level: .error)
            appendLogLine(logLine)
        }
    }

    func stop() {
        guard let proc = process else { return }
        statusMonitor.stopTimer()
        let pid = proc.processIdentifier

        Task.detached { [weak self] in
            guard let self else { return }
            let deadline = DispatchTime.now() + .seconds(5)

            proc.terminationHandler = { [weak self] _process in
                DispatchQueue.main.async {
                    self?.process = nil
                }
            }

            proc.terminate()

            while DispatchTime.now() < deadline {
                if self.process == nil { break }
                try? await Task.sleep(for: .milliseconds(50))
            }

            if self.process != nil, kill(pid, 0) == 0 {
                kill(pid, SIGKILL)
            }
        }
    }

    func stopSynchronously() {
        guard let proc = process else { return }
        statusMonitor.stopTimer()
        let pid = proc.processIdentifier

        proc.terminationHandler = { [weak self] _process in
            DispatchQueue.main.async {
                self?.process = nil
            }
        }

        proc.terminate()

        let deadline = DispatchTime.now() + .seconds(5)
        while DispatchTime.now() < deadline {
            if process == nil { break }
            usleep(50_000)
        }

        if process != nil, kill(pid, 0) == 0 {
            kill(pid, SIGKILL)
        }
    }

    func restart() {
        let currentConfig = config
        stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.spawn(config: currentConfig)
        }
    }

    func clearLogs() {
        logLines.removeAll()
    }

    func classify(_ text: String) -> LogLine.LogLevel {
        if text.localizedCaseInsensitiveContains("t/s") {
            return .timing
        }
        if text.localizedCaseInsensitiveContains("gen=") {
            return .generation
        }
        if text.localizedCaseInsensitiveContains("prefill") {
            return .prefill
        }
        if text.localizedCaseInsensitiveContains("kv cache") {
            return .kvcache
        }
        if text.localizedCaseInsensitiveContains("tool calls") {
            return .tool
        }
        if text.localizedCaseInsensitiveContains("warning") {
            return .warning
        }
        if text.localizedCaseInsensitiveContains("failed") || text.localizedCaseInsensitiveContains("error") {
            return .error
        }
        return .info
    }
}
