import XCTest
import Foundation
@testable import App

final class StatusMonitorTests: XCTestCase {

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
}
