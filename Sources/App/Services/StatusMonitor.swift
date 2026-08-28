import Foundation
import SwiftUI
import IOKit

struct MetricsSnapshot {
    let timestamp: Date
    let prefillTokensPerSecond: Double
    let generationTokensPerSecond: Double
    let contextUsed: Int?
    let contextTotal: Int?
    let systemMemoryUsedMB: Double?
    let systemMemoryTotalMB: Double?
    let gpuLoadPercent: Double?
}

@Observable
final class StatusMonitor {
    var prefillTokensPerSecond: Double = 0
    var generationTokensPerSecond: Double = 0
    var contextUsed: Int? = nil
    var contextTotal: Int? = nil
    var maxContext: Int = 262144
    var systemMemoryUsedMB: Double? = nil
    var systemMemoryTotalMB: Double? = nil
    var gpuLoadPercent: Double? = nil

    private(set) var lifetimeMetrics: LifetimeMetrics

    private(set) var history: [MetricsSnapshot] = []
    private var timer: Timer?
    private var lastPrefillUpdate: Date?
    private var lastGenerationUpdate: Date?
    private let lifetimeMetricsStore: LifetimeMetricsStore
    private let lifetimeMetricsPersistenceQueue = DispatchQueue(
        label: "com.dwarfstarlauncher.lifetime-metrics-persistence",
        qos: .utility
    )
    private var pendingLifetimeMetricsPersistence: DispatchWorkItem?

    private struct PrefillProgress {
        let contextStart: Int64
        let total: Int64
        var current: Int64
        var didRecord: Bool
    }

    private var prefillProgress: PrefillProgress?
    private var lastGenerationTokenCount: Int64?
    private var lastGenerationElapsedSeconds: Double?

    init(lifetimeMetricsStore: LifetimeMetricsStore = LifetimeMetricsStore()) {
        self.lifetimeMetricsStore = lifetimeMetricsStore
        self.lifetimeMetrics = lifetimeMetricsStore.load()
    }

    var contextPercent: Double? {
        guard let used = contextUsed, let total = contextTotal, total > 0 else { return nil }
        return Double(used) / Double(total) * 100
    }

    // Precompiled once rather than rebuilt on every log line (these patterns are
    // static literals, so the `try!` is safe and only runs at class initialization).
    private static let prefillPattern = try! NSRegularExpression(pattern: #"chunk=[\d.]+\s*t/s\s+avg=([\d.]+)\s*t/s"#)
    private static let generationPattern = try! NSRegularExpression(pattern: #"decoding\s+chunk=[\d.]+\s*t/s\s+avg=([\d.]+)\s*t/s"#)
    private static let contextPattern = try! NSRegularExpression(pattern: #"ctx=(\d+)\.\.(\d+):(\d+)"#)
    private static let prefillProgressPattern = try! NSRegularExpression(pattern: #"\bprefill\s+chunk\s+(\d+)\s*/\s*(\d+)"#)
    private static let generationTokenPattern = try! NSRegularExpression(pattern: #"\bgen=(\d+)\b"#)
    private static let elapsedSecondsPattern = try! NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)s\s*$"#)

    func parse(_ line: String) {
        if line.localizedCaseInsensitiveContains("prompt start") {
            prefillProgress = nil
            lastGenerationTokenCount = nil
            lastGenerationElapsedSeconds = nil
        }

        // Prefill: lines contain "prefill" and "chunk=X.XX t/s"
        if line.localizedCaseInsensitiveContains("prefill") {
            let range = NSRange(line.startIndex..., in: line)
            if let match = Self.prefillPattern.firstMatch(in: line, range: range),
               let value = Double(line[Range(match.range(at: 1), in: line)!]) {
                prefillTokensPerSecond = value
                generationTokensPerSecond = 0
                lastPrefillUpdate = Date()
            }

            recordCompletedPrefillIfNeeded(in: line)
        }

        // Generation: "decoding chunk=X.XX t/s"
        let genRange = NSRange(line.startIndex..., in: line)
        if let match = Self.generationPattern.firstMatch(in: line, range: genRange),
           let value = Double(line[Range(match.range(at: 1), in: line)!]) {
            generationTokensPerSecond = value
            prefillTokensPerSecond = 0
            lastGenerationUpdate = Date()
        }

        recordGenerationIfNeeded(in: line)

        // Context: "ctx=START..END:USED" — use maxContext as total
        let ctxRange = NSRange(line.startIndex..., in: line)
        if let match = Self.contextPattern.firstMatch(in: line, range: ctxRange),
           let end = Int(line[Range(match.range(at: 2), in: line)!]) {
            contextUsed = end
            contextTotal = maxContext
        }

        let snapshot = MetricsSnapshot(
            timestamp: Date(),
            prefillTokensPerSecond: prefillTokensPerSecond,
            generationTokensPerSecond: generationTokensPerSecond,
            contextUsed: contextUsed,
            contextTotal: contextTotal,
            systemMemoryUsedMB: systemMemoryUsedMB,
            systemMemoryTotalMB: systemMemoryTotalMB,
            gpuLoadPercent: gpuLoadPercent
        )

        if history.last == nil || differs(history.last!, snapshot) {
            history.append(snapshot)
            if history.count > 1000 {
                history.removeFirst(history.count - 1000)
            }
        }
    }

    // MARK: - Lifetime metrics

    private func recordCompletedPrefillIfNeeded(in line: String) {
        let range = NSRange(line.startIndex..., in: line)
        guard let progressMatch = Self.prefillProgressPattern.firstMatch(in: line, range: range),
              let current = Int64(line[Range(progressMatch.range(at: 1), in: line)!]),
              let total = Int64(line[Range(progressMatch.range(at: 2), in: line)!]),
              total > 0 else { return }

        let contextRange = Self.contextPattern.firstMatch(in: line, range: range)
        let contextStart = contextRange.flatMap { Int64(line[Range($0.range(at: 1), in: line)!]) } ?? 0
        let contextEnd = contextRange.flatMap { Int64(line[Range($0.range(at: 2), in: line)!]) }

        let startsNewPrefill = prefillProgress.map {
            current == 0
                || $0.total != total
                || $0.contextStart != contextStart
                || current < $0.current
        } ?? true

        if startsNewPrefill {
            prefillProgress = PrefillProgress(
                contextStart: contextStart,
                total: total,
                current: current,
                didRecord: false
            )
        } else {
            prefillProgress?.current = current
        }

        guard current >= total, prefillProgress?.didRecord == false else { return }

        let tokenCount = max((contextEnd ?? total) - contextStart, 0)
        let speed = value(for: Self.prefillPattern, in: line)
        let duration = elapsedDuration(for: tokenCount, speed: speed, in: line)
        lifetimeMetrics.addPrefill(tokens: tokenCount, duration: duration)
        prefillProgress?.didRecord = true
        persistLifetimeMetrics()
    }

    private func recordGenerationIfNeeded(in line: String) {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = Self.generationTokenPattern.firstMatch(in: line, range: range),
              let tokenCount = Int64(line[Range(match.range(at: 1), in: line)!]) else { return }

        let previousCount = lastGenerationTokenCount ?? 0
        if tokenCount < previousCount {
            // A lower cumulative count indicates a new request even if the
            // server did not emit a prompt-start line between requests.
            lastGenerationTokenCount = 0
            lastGenerationElapsedSeconds = nil
        }

        let countBeforeThisLine = lastGenerationTokenCount ?? 0
        let delta = tokenCount - countBeforeThisLine
        guard delta > 0 else {
            lastGenerationTokenCount = tokenCount
            return
        }

        let speed = value(for: Self.generationPattern, in: line)
        let elapsed = value(for: Self.elapsedSecondsPattern, in: line)
        let duration: Double?
        if let elapsed, let previousElapsed = lastGenerationElapsedSeconds, elapsed > previousElapsed {
            duration = elapsed - previousElapsed
        } else if lastGenerationElapsedSeconds != nil {
            // Some server log formats report a per-line duration rather than a
            // cumulative one. Fall back to the measured throughput in that case.
            duration = speed.map { Double(delta) / $0 }
        } else {
            duration = elapsed ?? speed.map { Double(delta) / $0 }
        }

        lifetimeMetrics.addGeneration(tokens: delta, duration: duration)
        lastGenerationTokenCount = tokenCount
        lastGenerationElapsedSeconds = elapsed
        persistLifetimeMetrics()
    }

    private func elapsedDuration(for tokens: Int64, speed: Double?, in line: String) -> Double? {
        if let elapsed = value(for: Self.elapsedSecondsPattern, in: line), elapsed > 0 {
            return elapsed
        }
        guard let speed, speed > 0, tokens > 0 else { return nil }
        return Double(tokens) / speed
    }

    private func value(for pattern: NSRegularExpression, in line: String) -> Double? {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = pattern.firstMatch(in: line, range: range),
              let valueRange = Range(match.range(at: 1), in: line) else { return nil }
        return Double(line[valueRange])
    }

    private func persistLifetimeMetrics() {
        pendingLifetimeMetricsPersistence?.cancel()

        let metrics = lifetimeMetrics
        let store = lifetimeMetricsStore
        let workItem = DispatchWorkItem {
            try? store.save(metrics)
        }
        pendingLifetimeMetricsPersistence = workItem
        lifetimeMetricsPersistenceQueue.asyncAfter(
            deadline: .now() + .seconds(1),
            execute: workItem
        )
    }

    /// Flushes the latest in-memory snapshot. Used during orderly app
    /// termination so the short opportunistic write window does not matter.
    func flushLifetimeMetrics() {
        pendingLifetimeMetricsPersistence?.cancel()
        pendingLifetimeMetricsPersistence = nil

        let metrics = lifetimeMetrics
        let store = lifetimeMetricsStore
        lifetimeMetricsPersistenceQueue.sync {
            try? store.save(metrics)
        }
    }

    func resetLifetimeMetrics() {
        lifetimeMetrics = LifetimeMetrics()
        flushLifetimeMetrics()
    }

    private func differs(_ lhs: MetricsSnapshot, _ rhs: MetricsSnapshot) -> Bool {
        lhs.prefillTokensPerSecond != rhs.prefillTokensPerSecond ||
        lhs.generationTokensPerSecond != rhs.generationTokensPerSecond ||
        lhs.contextUsed != rhs.contextUsed ||
        lhs.contextTotal != rhs.contextTotal ||
        lhs.systemMemoryUsedMB != rhs.systemMemoryUsedMB ||
        lhs.systemMemoryTotalMB != rhs.systemMemoryTotalMB ||
        lhs.gpuLoadPercent != rhs.gpuLoadPercent
    }

    // MARK: - System metrics

    func collectSystemMetrics() {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size) { p in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, p, &count)
            }
        }

        if result == KERN_SUCCESS {
            let pageSize = vm_page_size
            let used = Double(info.active_count + info.wire_count) * Double(pageSize) / 1_048_576
            let total = Double(ProcessInfo.processInfo.physicalMemory) / 1_048_576
            systemMemoryUsedMB = used
            systemMemoryTotalMB = total
        }
    }

    func collectGPU() {
        let matching = IOServiceMatching("IOAccelerator")
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            gpuLoadPercent = nil
            return
        }
        defer { IOObjectRelease(iterator) }

        var service: io_object_t = IOIteratorNext(iterator)
        while service != 0 {
            var statistics: Unmanaged<CFMutableDictionary>?
            let ret = IORegistryEntryCreateCFProperties(service, &statistics, kCFAllocatorDefault, 0)
            if ret == KERN_SUCCESS, let stats = statistics?.takeRetainedValue() as? [String: Any] {
                if let perfStats = stats["PerformanceStatistics"] as? [String: Any] {
                    if let gpuUtil = perfStats["GPU Core Utilization"] as? Double {
                        gpuLoadPercent = min(max(gpuUtil, 0), 100)
                    } else if let devUtil = perfStats["Device Utilization %"] as? Double {
                        gpuLoadPercent = min(max(devUtil, 0), 100)
                    }
                }
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
    }

    func startTimer() {
        // Invalidate any pre-existing timer so a replacement never leaks a
        // still-scheduled timer. Guaranteed by the method itself, not by a
        // `spawn()` guard in another class.
        timer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            collectSystemMetrics()
            collectGPU()

            // Expire stale throughput values after 3 seconds of inactivity
            if let last = lastPrefillUpdate, Date().timeIntervalSince(last) > 3 {
                prefillTokensPerSecond = 0
            }
            if let last = lastGenerationUpdate, Date().timeIntervalSince(last) > 3 {
                generationTokensPerSecond = 0
            }

            let snapshot = MetricsSnapshot(
                timestamp: Date(),
                prefillTokensPerSecond: prefillTokensPerSecond,
                generationTokensPerSecond: generationTokensPerSecond,
                contextUsed: contextUsed,
                contextTotal: contextTotal,
                systemMemoryUsedMB: systemMemoryUsedMB,
                systemMemoryTotalMB: systemMemoryTotalMB,
                gpuLoadPercent: gpuLoadPercent
            )
            if history.last == nil || differs(history.last!, snapshot) {
                history.append(snapshot)
                if history.count > 1000 {
                    history.removeFirst(history.count - 1000)
                }
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .default)
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    func reset() {
        prefillTokensPerSecond = 0
        generationTokensPerSecond = 0
        contextUsed = nil
        contextTotal = nil
        systemMemoryUsedMB = nil
        systemMemoryTotalMB = nil
        gpuLoadPercent = nil
        lastPrefillUpdate = nil
        lastGenerationUpdate = nil
        prefillProgress = nil
        lastGenerationTokenCount = nil
        lastGenerationElapsedSeconds = nil
        history.removeAll()
        stopTimer()
    }
}
