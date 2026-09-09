import XCTest
import Foundation
@testable import App

final class ConfigStoreTests: XCTestCase {
    func testTokenOnlyFileDecodesFullServerConfigWithDefaults() throws {
        let directory = appMakeTempDirectory()
        let store = ConfigStore(fileURL: directory.appendingPathComponent("nested/config.json"))
        try store.updateJSONObject { object in
            object["hfToken"] = "hf_test"
        }

        let config = try XCTUnwrap(store.load(ServerConfig.self))
        XCTAssertEqual(config.hfToken, "hf_test")
        XCTAssertEqual(config.modelPath, "")
        XCTAssertNil(config.visionEncoderPath)
        XCTAssertFalse(config.enableVision)
        XCTAssertEqual(config.host, "127.0.0.1")
        XCTAssertEqual(config.port, 1234)
        XCTAssertTrue(config.enableMtp)
        XCTAssertFalse(config.useEmbeddedMtp)
    }

    func testConcurrentReadModifyWriteUpdatesRemainValidAndComplete() throws {
        let directory = appMakeTempDirectory()
        let store = ConfigStore(fileURL: directory.appendingPathComponent("config.json"))
        try store.updateJSONObject { $0["seed"] = true }

        DispatchQueue.concurrentPerform(iterations: 40) { index in
            let writer = ConfigStore(fileURL: store.fileURL)
            try? writer.updateJSONObject { object in
                object["writer-\(index)"] = index
            }
        }

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: store.fileURL)) as? [String: Any]
        )
        XCTAssertEqual(object["seed"] as? Bool, true)
        for index in 0..<40 {
            XCTAssertEqual(object["writer-\(index)"] as? Int, index)
        }
    }

    func testConfigFileIsOwnerReadableAndWritableOnly() throws {
        let directory = appMakeTempDirectory()
        let store = ConfigStore(fileURL: directory.appendingPathComponent("config.json"))
        try store.save(ServerConfig())

        let attributes = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
}
