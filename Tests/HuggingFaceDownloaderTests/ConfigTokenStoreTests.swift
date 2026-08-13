import XCTest
import Foundation
@testable import HuggingFaceDownloader

final class ConfigTokenStoreTests: XCTestCase {

    private var configURL: URL!

    override func setUp() {
        super.setUp()
        resetTokenCache()
        configURL = makeTempConfigURL()
    }

    override func tearDown() {
        resetTokenCache()
        super.tearDown()
    }

    private func makeStore() -> ConfigTokenStore {
        ConfigTokenStore(fileURL: configURL)
    }

    // MARK: - save / load

    func testSaveThenLoadReturnsToken() throws {
        let store = makeStore()
        try store.save("hf_secret")

        XCTAssertEqual(makeStore().load(), "hf_secret")
        XCTAssertTrue(makeStore().exists())
    }

    func testLoadReturnsNilWhenFileDoesNotExist() {
        XCTAssertNil(makeStore().load())
        XCTAssertFalse(makeStore().exists())
    }

    func testSaveEmptyStringClearsToken() throws {
        let store = makeStore()
        try store.save("hf_secret")
        XCTAssertEqual(store.load(), "hf_secret")

        try store.save("")
        XCTAssertNil(makeStore().load())
        XCTAssertFalse(makeStore().exists())
    }

    func testDeleteClearsTokenAndFileEntry() throws {
        let store = makeStore()
        try store.save("hf_secret")
        XCTAssertTrue(store.exists())

        try store.delete()
        XCTAssertNil(makeStore().load())
        XCTAssertFalse(store.exists())
    }

    // MARK: - persistence across instances

    func testTokenPersistsToDiskAfterCacheReset() throws {
        let store = makeStore()
        try store.save("hf_persisted")

        // Simulate a fresh session: reset the static in-memory cache and read
        // back from disk with a brand-new store instance.
        resetTokenCache()

        XCTAssertEqual(makeStore().load(), "hf_persisted")
    }

    func testCacheIsSharedAcrossInstances() throws {
        resetTokenCache()
        let first = makeStore()
        try first.save("hf_cached")

        // A second instance must observe the cached value without touching disk.
        XCTAssertEqual(makeStore().load(), "hf_cached")
    }

    // MARK: - coexistence with the full server config file

    func testWritePreservesOtherConfigKeys() throws {
        // Simulate an existing full config that also contains a contextSize key.
        let original = #"{"contextSize":262144,"power":100}"#
        try Data(original.utf8).write(to: configURL)

        let store = makeStore()
        try store.save("hf_token")

        let onDisk = try JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as? [String: Any]
        XCTAssertEqual(onDisk?["hfToken"] as? String, "hf_token")
        XCTAssertEqual(onDisk?["contextSize"] as? Int, 262144)
        XCTAssertEqual(onDisk?["power"] as? Int, 100)
    }

    func testDeleteRemovesOnlyHfTokenKey() throws {
        let original = #"{"contextSize":262144,"hfToken":"old-token"}"#
        try Data(original.utf8).write(to: configURL)

        let store = makeStore()
        try store.delete()

        let onDisk = try JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as? [String: Any]
        XCTAssertNil(onDisk?["hfToken"])
        XCTAssertEqual(onDisk?["contextSize"] as? Int, 262144)
    }
}
