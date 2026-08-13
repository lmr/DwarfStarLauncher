import XCTest
import Foundation
@testable import HuggingFaceDownloader

// MARK: - Mock URLProtocol
//
// Intercepts every URLSession request and serves canned responses, so
// DefaultHuggingFaceClient can be tested without network access.

final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func reset() {
        requests = []
        requestHandler = nil
    }
}

func makeMockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

func makeResponse(request: URLRequest, status: Int) -> HTTPURLResponse {
    HTTPURLResponse(url: request.url ?? URL(string: "https://huggingface.co")!,
                    statusCode: status, httpVersion: "HTTP/1.1", headerFields: [:])!
}

// MARK: - Temp file helpers

var tempCounter = 0

func makeTempDirectory() -> URL {
    tempCounter += 1
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("DwarfStarTests-\(ProcessInfo.processInfo.processIdentifier)-\(tempCounter)")
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

func makeTempConfigURL() -> URL {
    makeTempDirectory().appendingPathComponent("config.json")
}

/// Resets the static in-memory token cache so tests are isolated from each other.
/// Uses a temp-backed store so no real user config file is touched.
func resetTokenCache() {
    let store = ConfigTokenStore(fileURL: makeTempConfigURL())
    try? store.delete()
}
