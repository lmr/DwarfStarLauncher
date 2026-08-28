import XCTest
import Foundation
@testable import App

final class StatusMonitorTests: XCTestCase {

    private func makeMetricsStore() -> LifetimeMetricsStore {
        let directory = appMakeTempDirectory()
        return LifetimeMetricsStore(fileURL: directory.appendingPathComponent("lifetime_metrics.json"))
    }

    func testParsesPrefillThroughput() {
        let monitor = StatusMonitor()
        monitor.parse("prefill chunk=12.34 t/s avg=56.78 t/s")
        XCTAssertEqual(monitor.prefillTokensPerSecond, 56.78)
        XCTAssertEqual(monitor.generationTokensPerSecond, 0)
    }

    func testParsesGenerationThroughput() {
        let monitor = StatusMonitor()
        monitor.parse("decoding chunk=1.23 t/s avg=45.67 t/s")
        XCTAssertEqual(monitor.generationTokensPerSecond, 45.67)
        XCTAssertEqual(monitor.prefillTokensPerSecond, 0)
    }

    func testRecordsCompletedPrefillTokensAndPersistsThem() {
        let store = makeMetricsStore()
        let monitor = StatusMonitor(lifetimeMetricsStore: store)

        monitor.parse("chat ctx=0..100:100 prompt start")
        monitor.parse("chat ctx=0..100:100 prefill chunk 0/100 (0.0%) chunk=0.00 t/s avg=0.00 t/s 0.000s")
        monitor.parse("chat ctx=0..100:100 prefill chunk 100/100 (100.0%) chunk=50.00 t/s avg=50.00 t/s 2.000s")
        monitor.flushLifetimeMetrics()

        XCTAssertEqual(monitor.lifetimeMetrics.prefilledTokenCount, 100)
        XCTAssertEqual(monitor.lifetimeMetrics.averagePrefillTokensPerSecond ?? 0, 50, accuracy: 0.001)
        XCTAssertEqual(store.load(), monitor.lifetimeMetrics)
    }

    func testRecordsCumulativeGenerationTokensOnlyOnce() {
        let monitor = StatusMonitor(lifetimeMetricsStore: makeMetricsStore())

        monitor.parse("chat ctx=0..100:100 prompt start")
        monitor.parse("chat ctx=100..110:10 gen=10 decoding chunk=10.00 t/s avg=10.00 t/s 1.000s")
        monitor.parse("chat ctx=100..130:30 gen=30 decoding chunk=20.00 t/s avg=15.00 t/s 2.000s")
        monitor.parse("chat ctx=100..130:30 gen=30 decoding chunk=20.00 t/s avg=15.00 t/s 2.000s")

        XCTAssertEqual(monitor.lifetimeMetrics.generatedTokenCount, 30)
        XCTAssertEqual(monitor.lifetimeMetrics.averageGenerationTokensPerSecond ?? 0, 15, accuracy: 0.001)
    }

    func testLifetimeMetricsLoadAcrossMonitorInstances() {
        let store = makeMetricsStore()
        let firstMonitor = StatusMonitor(lifetimeMetricsStore: store)
        firstMonitor.parse("chat ctx=0..50:50 prompt start")
        firstMonitor.parse("chat ctx=0..50:50 prefill chunk 50/50 (100.0%) chunk=25.00 t/s avg=25.00 t/s 2.000s")
        firstMonitor.flushLifetimeMetrics()

        let secondMonitor = StatusMonitor(lifetimeMetricsStore: store)

        XCTAssertEqual(secondMonitor.lifetimeMetrics.prefilledTokenCount, 50)
        XCTAssertEqual(secondMonitor.lifetimeMetrics.averagePrefillTokensPerSecond ?? 0, 25, accuracy: 0.001)
    }

    func testAverageSpeedIsWeightedByTokenProcessingTime() {
        let monitor = StatusMonitor(lifetimeMetricsStore: makeMetricsStore())

        monitor.parse("chat ctx=0..100:100 prompt start")
        monitor.parse("chat ctx=0..100:100 prefill chunk 100/100 (100.0%) chunk=50.00 t/s avg=50.00 t/s 2.000s")
        monitor.parse("chat ctx=100..200:100 prompt start")
        monitor.parse("chat ctx=100..200:100 prefill chunk 200/200 (100.0%) chunk=100.00 t/s avg=100.00 t/s 1.000s")

        XCTAssertEqual(monitor.lifetimeMetrics.prefilledTokenCount, 200)
        XCTAssertEqual(monitor.lifetimeMetrics.averagePrefillTokensPerSecond ?? 0, 200.0 / 3.0, accuracy: 0.001)
    }

    func testResetClearsLiveMetricsButKeepsLifetimeMetrics() {
        let monitor = StatusMonitor(lifetimeMetricsStore: makeMetricsStore())
        monitor.parse("chat ctx=0..50:50 prompt start")
        monitor.parse("chat ctx=0..50:50 prefill chunk 50/50 (100.0%) chunk=25.00 t/s avg=25.00 t/s 2.000s")

        monitor.reset()

        XCTAssertTrue(monitor.history.isEmpty)
        XCTAssertEqual(monitor.lifetimeMetrics.prefilledTokenCount, 50)
    }

    func testParsesContextUsage() {
        let monitor = StatusMonitor()
        monitor.parse("ctx=0..2048:1024")
        // parse() sets contextUsed to the END value of the ctx range.
        XCTAssertEqual(monitor.contextUsed, 2048)
        XCTAssertEqual(monitor.contextTotal, 262144) // default maxContext
    }

    func testContextPercent() {
        let monitor = StatusMonitor()
        monitor.maxContext = 1000
        monitor.parse("ctx=0..250:250")
        XCTAssertEqual(monitor.contextPercent ?? -1, 25.0)
    }

    func testContextPercentNilWhenNoContext() {
        let monitor = StatusMonitor()
        XCTAssertNil(monitor.contextPercent)
    }

    func testHistoryCapsAt1000() {
        let monitor = StatusMonitor()
        for i in 1...2000 {
            monitor.parse("ctx=0..\(i):\(i)")
        }
        XCTAssertEqual(monitor.history.count, 1000)
    }

    func testHistoryDoesNotDuplicateIdenticalSnapshots() {
        let monitor = StatusMonitor()
        monitor.parse("ctx=0..100:50")
        monitor.parse("ctx=0..100:50")
        XCTAssertEqual(monitor.history.count, 1)
    }

    func testResetClearsState() {
        let monitor = StatusMonitor()
        monitor.parse("decoding chunk=1.23 t/s avg=45.67 t/s")
        monitor.reset()
        XCTAssertEqual(monitor.generationTokensPerSecond, 0)
        XCTAssertNil(monitor.contextUsed)
        XCTAssertTrue(monitor.history.isEmpty)
    }
}

final class ServerManagerTests: XCTestCase {

    private let manager = ServerManager(statusMonitor: StatusMonitor())

    func testClassifyTiming() {
        XCTAssertEqual(manager.classify("generation tokens 12.3 t/s"), .timing)
    }

    func testClassifyGeneration() {
        XCTAssertEqual(manager.classify("gen=1.2"), .generation)
    }

    func testClassifyPrefill() {
        XCTAssertEqual(manager.classify("prefill phase"), .prefill)
    }

    func testClassifyKvCache() {
        XCTAssertEqual(manager.classify("kv cache full"), .kvcache)
    }

    func testClassifyTool() {
        XCTAssertEqual(manager.classify("tool calls: 2"), .tool)
    }

    func testClassifyWarning() {
        XCTAssertEqual(manager.classify("warning: low memory"), .warning)
    }

    func testClassifyError() {
        XCTAssertEqual(manager.classify("failed to load model"), .error)
        XCTAssertEqual(manager.classify("error: oom"), .error)
    }

    func testClassifyInfoFallback() {
        XCTAssertEqual(manager.classify("server listening on port 1234"), .info)
    }

    func testLogLinesAreCappedAtLimit() {
        let manager = ServerManager(statusMonitor: StatusMonitor())
        for i in 0..<12_000 {
            manager.appendLogLine(LogLine(timestamp: Date(), text: "line \(i)", level: .info))
        }
        XCTAssertEqual(manager.logLines.count, 10_000)
        XCTAssertEqual(manager.logLines.last?.text, "line 11999")
        // The oldest lines were trimmed away, keeping the most recent 10k.
        XCTAssertEqual(manager.logLines.first?.text, "line 2000")
    }
}
