import XCTest
import Foundation
@testable import HuggingFaceDownloader

final class DefaultHuggingFaceClientTests: XCTestCase {

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        resetTokenCache()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        resetTokenCache()
        super.tearDown()
    }

    // MARK: - resolveFilePath

    func testResolveFilePathDecodesResponse() async throws {
        let json = #"{"path":"models/DeepSeek-V4-Flash.gguf","size":12345,"oid":"abc123","lfs":null}"#
            .data(using: .utf8)!
        MockURLProtocol.requestHandler = { request in
            (makeResponse(request: request, status: 200), json)
        }

        let client = DefaultHuggingFaceClient(session: makeMockSession())
        let result = try await client.resolveFilePath(repo: "antirez/deepseek-v4-gguf", path: "DeepSeek-V4-Flash.gguf")

        XCTAssertEqual(result.path, "models/DeepSeek-V4-Flash.gguf")
        XCTAssertEqual(result.size, 12345)
        XCTAssertEqual(result.oid, "abc123")
        XCTAssertNil(result.lfs)
    }

    func testResolveFilePathBuildsCorrectRequest() async throws {
        let json = #"{"path":"x","size":1,"oid":"o","lfs":null}"#.data(using: .utf8)!
        MockURLProtocol.requestHandler = { request in
            (makeResponse(request: request, status: 200), json)
        }

        let client = DefaultHuggingFaceClient(session: makeMockSession())
        _ = try await client.resolveFilePath(repo: "antirez/deepseek-v4-gguf", path: "DeepSeek-V4-Flash.gguf")

        let request = MockURLProtocol.requests.last!
        XCTAssertEqual(request.url?.absoluteString,
                       "https://huggingface.co/api/models/antirez/deepseek-v4-gguf/tree/main/DeepSeek-V4-Flash.gguf")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/octet-stream")
    }

    func testResolveFilePathThrowsFileNotFoundOnNon200() async {
        MockURLProtocol.requestHandler = { request in
            (makeResponse(request: request, status: 404), Data())
        }

        let client = DefaultHuggingFaceClient(session: makeMockSession())
        do {
            _ = try await client.resolveFilePath(repo: "r", path: "p")
            XCTFail("Expected fileNotFound error")
        } catch {
            XCTAssertEqual((error as? HFClientError), .fileNotFound)
        }
    }

    // MARK: - resolveDownloadUrl

    func testResolveDownloadUrlSetsRedirectHeaderAndDecodes() async throws {
        let json = #"{"location":"https://cdn.hf.co/file.gguf","lfs":{"oid":"oid1","size":42,"url":"https://cdn.hf.co/lfs"}}"#
            .data(using: .utf8)!
        MockURLProtocol.requestHandler = { request in
            (makeResponse(request: request, status: 200), json)
        }

        let client = DefaultHuggingFaceClient(session: makeMockSession())
        let result = try await client.resolveDownloadUrl(repo: "antirez/deepseek-v4-gguf", path: "file.gguf")

        XCTAssertEqual(result.location, "https://cdn.hf.co/file.gguf")
        XCTAssertEqual(result.lfs?.oid, "oid1")
        XCTAssertEqual(result.lfs?.size, 42)

        let request = MockURLProtocol.requests.last!
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Reference-Redirect"), "redirect=false")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/octet-stream")
    }

    func testResolveDownloadUrlThrowsDownloadUrlNotFoundOnNon200() async {
        MockURLProtocol.requestHandler = { request in
            (makeResponse(request: request, status: 500), Data())
        }

        let client = DefaultHuggingFaceClient(session: makeMockSession())
        do {
            _ = try await client.resolveDownloadUrl(repo: "r", path: "p")
            XCTFail("Expected downloadUrlNotFound error")
        } catch {
            XCTAssertEqual((error as? HFClientError), .downloadUrlNotFound)
        }
    }

    // MARK: - listFiles

    func testListFilesDecodesArray() async throws {
        let json = """
        [
          {"path":"a.gguf","size":10,"oid":"o1","lfs":null},
          {"path":"b.gguf","size":20,"oid":"o2","lfs":null}
        ]
        """.data(using: .utf8)!
        MockURLProtocol.requestHandler = { request in
            (makeResponse(request: request, status: 200), json)
        }

        let client = DefaultHuggingFaceClient(session: makeMockSession())
        let result = try await client.listFiles(repo: "antirez/deepseek-v4-gguf", path: "")

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].path, "a.gguf")
        XCTAssertEqual(result[1].size, 20)
    }

    func testListFilesThrowsFileNotFoundOnNon200() async {
        MockURLProtocol.requestHandler = { request in
            (makeResponse(request: request, status: 403), Data())
        }

        let client = DefaultHuggingFaceClient(session: makeMockSession())
        do {
            _ = try await client.listFiles(repo: "r")
            XCTFail("Expected fileNotFound error")
        } catch {
            XCTAssertEqual((error as? HFClientError), .fileNotFound)
        }
    }

    // MARK: - Auth header

    func testResolveFilePathSetsBearerTokenFromTokenStore() async throws {
        resetTokenCache()
        let store = ConfigTokenStore(fileURL: makeTempConfigURL())
        try store.save("test-token")

        let json = #"{"path":"x","size":1,"oid":"o","lfs":null}"#.data(using: .utf8)!
        MockURLProtocol.requestHandler = { request in
            (makeResponse(request: request, status: 200), json)
        }

        let client = DefaultHuggingFaceClient(session: makeMockSession(), tokenStore: store)
        _ = try await client.resolveFilePath(repo: "r", path: "p")

        XCTAssertEqual(MockURLProtocol.requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
    }

    // MARK: - Decoding failures

    func testResolveFilePathPropagatesDecodingError() async {
        let bad = Data("not json".utf8)
        MockURLProtocol.requestHandler = { request in
            (makeResponse(request: request, status: 200), bad)
        }

        let client = DefaultHuggingFaceClient(session: makeMockSession())
        do {
            _ = try await client.resolveFilePath(repo: "r", path: "p")
            XCTFail("Expected decoding error")
        } catch {
            // Any error other than HFClientError is acceptable (DecodingError).
            XCTAssertFalse(error is HFClientError)
        }
    }
}
