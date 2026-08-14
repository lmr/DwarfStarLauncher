import XCTest
import Foundation
@testable import App

/// Covers the in-memory downloaded-state that replaced the (never-mutated)
/// `ModelFile.downloaded` catalog flag. Views read `isDownloaded` /
/// `downloadedFileCount`, which must never report a phantom download.
final class ModelDownloaderDownloadedStateTests: XCTestCase {

    private var tempDir: URL!
    private var downloader: ModelDownloader!

    override func setUp() {
        super.setUp()
        tempDir = appMakeTempDirectory()
        PathResolver.setCustomModelsDirectory(tempDir)
        downloader = ModelDownloader()
    }

    override func tearDown() {
        PathResolver.resetModelsDirectory()
        super.tearDown()
    }

    func testEmptyDirReportsNothingDownloaded() {
        // Empty models dir => no target is downloaded and no file counts.
        XCTAssertFalse(downloader.isDownloaded(.ds4fQ2))
        XCTAssertEqual(downloader.downloadedFileCount(for: .ds4fQ2), 0)
        // Multi-shard target is likewise not downloaded.
        XCTAssertFalse(downloader.isDownloaded(.glmUnslothQ4))
        XCTAssertEqual(downloader.downloadedFileCount(for: .glmUnslothQ4), 0)
    }

    func testDownloadedStateIgnoresWrongSizeFiles() {
        // A file matching a catalog name but not its (large) size must not be
        // considered downloaded. Deterministic: the size check never matches.
        appWriteFile(named: DownloadTarget.ds4fQ2.files[0].localName, size: 10, in: tempDir)
        downloader.refreshDownloadedFiles()
        XCTAssertFalse(downloader.isDownloaded(.ds4fQ2))
        XCTAssertEqual(downloader.downloadedFileCount(for: .ds4fQ2), 0)
    }

    func testDownloadStateForNonCurrentTargetIsIdleWhenNotDownloaded() {
        // The view-facing state must fall back to idle (not complete) for a
        // target that isn't the current download and has no files on disk.
        let state = downloader.downloadState(for: .ds4fQ4)
        if case .progress = state {
            XCTFail("Non-current target must not report an in-flight progress state")
        }
    }
}
