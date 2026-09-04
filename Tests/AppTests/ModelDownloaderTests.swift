import XCTest
import Foundation
@testable import App
import HuggingFaceDownloader

private final class MockDownloadURLProtocol: URLProtocol {
    static var statusCode = 200
    static var responseData = Data()
    static var responseProvider: ((URLRequest) -> Data)?
    static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: [:]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if Self.statusCode == 200 || Self.statusCode == 206 {
            client?.urlProtocol(self, didLoad: Self.responseProvider?(request) ?? Self.responseData)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func reset() {
        statusCode = 200
        responseData = Data()
        responseProvider = nil
        requests = []
    }
}

private struct StubDownloadClient: HuggingFaceClient {
    let dataForPath: (String) -> Data

    func resolveFilePath(repo: String, path: String) async throws -> ResolvedFilePath {
        let data = dataForPath(path)
        return ResolvedFilePath(path: path, size: Int64(data.count), oid: "", lfs: nil)
    }

    func resolveDownloadUrl(repo: String, path: String) async throws -> DownloadUrl {
        fatalError("not used")
    }

    func listFiles(repo: String, path: String) async throws -> [ResolvedFilePath] {
        fatalError("not used")
    }
}

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
        MockDownloadURLProtocol.reset()
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

    func testHTTPFailuresSurfaceSpecificMessages() {
        let expectedMessages: [(Int, String)] = [
            (401, "Authentication failed"),
            (404, "File not found"),
            (429, "Rate limited")
        ]

        for (status, expected) in expectedMessages {
            let downloader = makeDownloader(data: Data("GGUFdata".utf8))
            downloader.availableTargets = [.ds4fDspark]
            MockDownloadURLProtocol.statusCode = status

            let expectation = expectation(description: "HTTP \(status) error")
            downloader.onDownloadError = { message in
                XCTAssertTrue(message.contains(expected))
                expectation.fulfill()
            }
            downloader.download(target: .ds4fDspark)
            wait(for: [expectation], timeout: 2)
        }
    }

    func testResumeWithHTTP200DiscardsPartialWithoutAppending() throws {
        let payload = Data("GGUFfresh-payload".utf8)
        let file = DownloadTarget.ds4fDspark.files[0]
        try Data("GGUFold-partial".utf8).write(to: PathResolver.partFileURL(for: file.localName))

        let downloader = makeDownloader(data: payload)
        downloader.availableTargets = [.ds4fDspark]
        let expectation = expectation(description: "resume rejection")
        downloader.onDownloadError = { message in
            XCTAssertTrue(message.contains("ignored the resume range"))
            expectation.fulfill()
        }

        downloader.download(target: .ds4fDspark)
        wait(for: [expectation], timeout: 2)

        XCTAssertFalse(FileManager.default.fileExists(atPath: PathResolver.partFileURL(for: file.localName).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: PathResolver.modelsDir.appendingPathComponent(file.localName).path))
        XCTAssertEqual(MockDownloadURLProtocol.requests.count, 1)
        XCTAssertNotNil(MockDownloadURLProtocol.requests[0].value(forHTTPHeaderField: "Range"))
    }

    func testIntegrityFailureDeletesPartialFile() {
        let downloader = makeDownloader(data: Data("not-a-gguf".utf8))
        downloader.availableTargets = [.ds4fDspark]
        let file = DownloadTarget.ds4fDspark.files[0]
        let expectation = expectation(description: "integrity error")
        downloader.onDownloadError = { message in
            XCTAssertTrue(message.contains("Integrity check failed"))
            expectation.fulfill()
        }

        downloader.download(target: .ds4fDspark)
        wait(for: [expectation], timeout: 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: PathResolver.partFileURL(for: file.localName).path))
    }

    func testMultiFileDownloadUsesResolvedPerFileSizesAndSequencesFiles() {
        let first = Data("GGUF-first-shard".utf8)
        let second = Data("GGUF-second-shard-with-a-different-size".utf8)
        MockDownloadURLProtocol.responseProvider = { request in
            request.url?.path.contains("Layers00-30") == true ? first : second
        }

        let downloader = makeDownloader(data: first) { path in
            path.contains("Layers00-30") ? first : second
        }
        downloader.availableTargets = [.proQ4Split]
        let expectation = expectation(description: "multi-file completion")
        downloader.onDownloadComplete = { target in
            XCTAssertEqual(target, .proQ4Split)
            expectation.fulfill()
        }

        downloader.download(target: .proQ4Split)
        wait(for: [expectation], timeout: 2)

        for file in DownloadTarget.proQ4Split.files {
            XCTAssertTrue(FileManager.default.fileExists(atPath: PathResolver.modelsDir.appendingPathComponent(file.localName).path))
        }
        XCTAssertEqual(MockDownloadURLProtocol.requests.count, 2)
    }

    private func makeDownloader(
        data: Data,
        dataForPath: ((String) -> Data)? = nil
    ) -> ModelDownloader {
        MockDownloadURLProtocol.responseData = data
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockDownloadURLProtocol.self]
        return ModelDownloader(
            huggingFaceClient: StubDownloadClient(dataForPath: dataForPath ?? { _ in data }),
            tokenStore: ConfigTokenStore(fileURL: tempDir.appendingPathComponent("config.json")),
            sessionConfiguration: config
        )
    }
}
