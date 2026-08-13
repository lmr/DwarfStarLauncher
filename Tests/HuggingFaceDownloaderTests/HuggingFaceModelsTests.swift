import XCTest
import Foundation
@testable import HuggingFaceDownloader

final class HuggingFaceModelsTests: XCTestCase {

    // MARK: - Codable round-trips

    func testResolvedFilePathCodableRoundTrip() throws {
        let model = ResolvedFilePath(path: "models/a.gguf", size: 86_720_111_488, oid: "abc", lfs: nil)
        let data = try JSONEncoder().encode(model)
        let decoded = try JSONDecoder().decode(ResolvedFilePath.self, from: data)
        XCTAssertEqual(decoded, model)
    }

    func testResolvedFilePathDecodesLfsInfo() throws {
        let json = #"{"path":"p","size":10,"oid":"o","lfs":{"oid":"lfs-oid","size":9,"url":"https://x"}}"#
        let decoded = try JSONDecoder().decode(ResolvedFilePath.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.lfs?.oid, "lfs-oid")
        XCTAssertEqual(decoded.lfs?.size, 9)
        XCTAssertEqual(decoded.lfs?.url, "https://x")
    }

    func testDownloadUrlCodableRoundTrip() throws {
        let model = DownloadUrl(location: "https://cdn.hf.co/f.gguf", lfs: LfsInfo(oid: "o", size: 5, url: "https://u"))
        let data = try JSONEncoder().encode(model)
        let decoded = try JSONDecoder().decode(DownloadUrl.self, from: data)
        XCTAssertEqual(decoded, model)
    }

    // MARK: - Equatable

    func testResolvedFilePathEquatableIgnoresLfsPresence() {
        let a = ResolvedFilePath(path: "p", size: 10, oid: "o", lfs: nil)
        let b = ResolvedFilePath(path: "p", size: 10, oid: "o", lfs: LfsInfo(oid: "x", size: 1, url: nil))
        XCTAssertEqual(a.path, b.path)
        XCTAssertEqual(a.size, b.size)
    }

    // MARK: - Error descriptions

    func testHFClientErrorDescriptions() {
        XCTAssertEqual(HFClientError.fileNotFound.errorDescription, "File not found on Hugging Face Hub.")
        XCTAssertEqual(HFClientError.downloadUrlNotFound.errorDescription, "Could not resolve download URL.")
    }
}
