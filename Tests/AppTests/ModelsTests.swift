import XCTest
import Foundation
@testable import App

final class ServerStatusTests: XCTestCase {
    func testLabels() {
        XCTAssertEqual(ServerStatus.starting.label, "Starting")
        XCTAssertEqual(ServerStatus.running.label, "Running")
        XCTAssertEqual(ServerStatus.stopped.label, "Stopped")
        XCTAssertEqual(ServerStatus.error(exitCode: 1).label, "Error")
    }

    func testColors() {
        XCTAssertEqual(ServerStatus.starting.color, "yellow")
        XCTAssertEqual(ServerStatus.running.color, "green")
        XCTAssertEqual(ServerStatus.stopped.color, "gray")
        XCTAssertEqual(ServerStatus.error(exitCode: 1).color, "red")
    }

    func testEquatable() {
        XCTAssertEqual(ServerStatus.error(exitCode: 1), ServerStatus.error(exitCode: 1))
        XCTAssertNotEqual(ServerStatus.error(exitCode: 1), ServerStatus.error(exitCode: 2))
        XCTAssertNotEqual(ServerStatus.running, ServerStatus.stopped)
    }
}

final class GGUFModelTests: XCTestCase {
    func testHumanReadableSize() {
        let kib = GGUFModel(path: "/a.gguf", name: "a.gguf", size: 1024)
        XCTAssertEqual(kib.humanReadableSize, "1 KB")

        let mib = GGUFModel(path: "/b.gguf", name: "b.gguf", size: 1_048_576)
        XCTAssertEqual(mib.humanReadableSize, "1 MB")
    }
}

final class DownloadStateTests: XCTestCase {
    func testEquatableProgress() {
        let a = DownloadState.progress(percent: 50, bytesDownloaded: 100, totalBytes: 200,
                                       speedBytesPerSec: 10, etaSeconds: 5)
        let b = DownloadState.progress(percent: 50, bytesDownloaded: 100, totalBytes: 200,
                                       speedBytesPerSec: 10, etaSeconds: 5)
        XCTAssertEqual(a, b)

        let c = DownloadState.progress(percent: 51, bytesDownloaded: 100, totalBytes: 200,
                                       speedBytesPerSec: 10, etaSeconds: 5)
        XCTAssertNotEqual(a, c)
    }

    func testIdleAndCompleteAreDistinct() {
        XCTAssertEqual(DownloadState.idle, DownloadState.idle)
        XCTAssertNotEqual(DownloadState.idle, DownloadState.complete)
    }
}

final class TokenCountFormatterTests: XCTestCase {
    func testHumanizesThousandsMillionsAndBillions() {
        XCTAssertEqual(TokenCountFormatter.humanize(999), "999")
        XCTAssertEqual(TokenCountFormatter.humanize(1_200), "1.2K")
        XCTAssertEqual(TokenCountFormatter.humanize(1_200_000), "1.2M")
        XCTAssertEqual(TokenCountFormatter.humanize(1_200_000_000), "1.2B")
    }

    func testPromotesRoundedValuesToTheNextUnit() {
        XCTAssertEqual(TokenCountFormatter.humanize(999_950), "1M")
        XCTAssertEqual(TokenCountFormatter.humanize(999_950_000), "1B")
    }
}
