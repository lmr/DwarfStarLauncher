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

    private(set) var history: [MetricsSnapshot] = []
    private var timer: Timer?
    private var lastPrefillUpdate: Date?
    private var lastGenerationUpdate: Date?

    var contextPercent: Double? {
        guard let used = contextUsed, let total = contextTotal, total > 0 else { return nil }
        return Double(used) / Double(total) * 100
    }

    func parse(_ line: String) {
        // Prefill: lines contain "prefill" and "chunk=X.XX t/s"
        if line.localizedCaseInsensitiveContains("prefill") {
            let chunkPattern = try! NSRegularExpression(pattern: #"chunk=[\d.]+\s*t/s\s+avg=([\d.]+)\s*t/s"#)
            let range = NSRange(line.startIndex..., in: line)
            if let match = chunkPattern.firstMatch(in: line, range: range),
               let value = Double(line[Range(match.range(at: 1), in: line)!]) {
                prefillTokensPerSecond = value
                generationTokensPerSecond = 0
                lastPrefillUpdate = Date()
            }
        }

        // Generation: "decoding chunk=X.XX t/s"
        let genPattern = try! NSRegularExpression(pattern: #"decoding\s+chunk=[\d.]+\s*t/s\s+avg=([\d.]+)\s*t/s"#)
        let genRange = NSRange(line.startIndex..., in: line)
        if let match = genPattern.firstMatch(in: line, range: genRange),
           let value = Double(line[Range(match.range(at: 1), in: line)!]) {
            generationTokensPerSecond = value
            prefillTokensPerSecond = 0
            lastGenerationUpdate = Date()
        }

        // Context: "ctx=START..END:USED" — use maxContext as total
        let ctxPattern = try! NSRegularExpression(pattern: #"ctx=(\d+)\.\.(\d+):(\d+)"#)
        let ctxRange = NSRange(line.startIndex..., in: line)
        if let match = ctxPattern.firstMatch(in: line, range: ctxRange),
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
        history.removeAll()
        stopTimer()
    }
}
