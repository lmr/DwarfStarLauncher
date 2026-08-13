import XCTest
import Foundation
@testable import App

// MARK: - Shared helpers for filesystem-based App tests

var appTempCounter = 0

func appMakeTempDirectory() -> URL {
    appTempCounter += 1
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("DwarfStarAppTests-\(ProcessInfo.processInfo.processIdentifier)-\(appTempCounter)")
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

func appWriteFile(named name: String, size: Int, in dir: URL) -> URL {
    let url = dir.appendingPathComponent(name)
    try! Data(repeating: 0x41, count: size).write(to: url)
    return url
}

// MARK: - ModelManager

final class ModelManagerTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = appMakeTempDirectory()
        PathResolver.setCustomModelsDirectory(tempDir)
    }

    override func tearDown() {
        PathResolver.resetModelsDirectory()
        super.tearDown()
    }

    private func seedFiles() {
        appWriteFile(named: "Model-A.gguf", size: 10, in: tempDir)
        appWriteFile(named: "Model-B.gguf", size: 20, in: tempDir)
        appWriteFile(named: "MTP-Model.gguf", size: 30, in: tempDir)
        appWriteFile(named: "DSPARK-Model.gguf", size: 40, in: tempDir)
        appWriteFile(named: "not-a-model.txt", size: 5, in: tempDir)
    }

    func testRefreshSeparatesMtpAndMainModels() {
        seedFiles()
        let manager = ModelManager()
        manager.refresh()

        XCTAssertEqual(manager.models.count, 2)
        XCTAssertEqual(manager.mtpModels.count, 2)

        // Sorted by size descending.
        XCTAssertEqual(manager.models.map(\.name), ["Model-B.gguf", "Model-A.gguf"])
        XCTAssertEqual(manager.mtpModels.map(\.name), ["DSPARK-Model.gguf", "MTP-Model.gguf"])
    }

    func testRefreshIgnoresNonGgufFiles() {
        seedFiles()
        let manager = ModelManager()
        manager.refresh()
        XCTAssertFalse(manager.models.contains { $0.name == "not-a-model.txt" })
    }

    func testRefreshReturnsEmptyWhenDirHasNoModels() {
        let manager = ModelManager()
        manager.refresh()
        XCTAssertEqual(manager.models.count, 0)
        XCTAssertEqual(manager.mtpModels.count, 0)
    }

    func testSelectModelByPath() {
        seedFiles()
        let manager = ModelManager()
        manager.refresh()

        let target = tempDir.appendingPathComponent("Model-A.gguf").path
        manager.selectModel(byPath: target)

        XCTAssertEqual(manager.selectedModel?.name, "Model-A.gguf")
        XCTAssertTrue(manager.models.first { $0.name == "Model-A.gguf" }?.isSelected == true)
        XCTAssertFalse(manager.models.first { $0.name == "Model-B.gguf" }?.isSelected == true)
    }

    func testSelectMtpModelByPathIgnoresMissingPath() {
        seedFiles()
        let manager = ModelManager()
        manager.refresh()
        manager.selectMtpModel(byPath: "/does/not/exist.gguf")
        XCTAssertNil(manager.selectedMtpModel)
    }
}

// MARK: - PathResolver

final class PathResolverTests: XCTestCase {

    override func tearDown() {
        PathResolver.resetModelsDirectory()
        super.tearDown()
    }

    func testDefaultPathsComposeFromHome() {
        PathResolver.resetModelsDirectory()
        let home = FileManager.default.homeDirectoryForCurrentUser
        XCTAssertEqual(PathResolver.dataRoot, home.appendingPathComponent(".ds4-launcher"))
        XCTAssertEqual(PathResolver.binDir, home.appendingPathComponent(".ds4-launcher/bin"))
        XCTAssertEqual(PathResolver.configFile, home.appendingPathComponent(".config/ds4-launcher/config.json"))
        XCTAssertEqual(PathResolver.serverBinary, home.appendingPathComponent(".ds4-launcher/bin/ds4-server"))
        XCTAssertEqual(PathResolver.modelsDir, home.appendingPathComponent(".ds4-launcher/models"))
    }

    func testSetCustomModelsDirectoryAndReset() {
        PathResolver.resetModelsDirectory()
        XCTAssertFalse(PathResolver.hasCustomModelsDirectory)

        let custom = appMakeTempDirectory()
        PathResolver.setCustomModelsDirectory(custom)
        XCTAssertTrue(PathResolver.hasCustomModelsDirectory)
        XCTAssertEqual(PathResolver.modelsDir.path, custom.path)

        PathResolver.resetModelsDirectory()
        XCTAssertFalse(PathResolver.hasCustomModelsDirectory)
        XCTAssertEqual(PathResolver.modelsDir, FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ds4-launcher/models"))
    }

    func testPartFileURLUsesModelsDir() {
        PathResolver.resetModelsDirectory()
        let url = PathResolver.partFileURL(for: "model.gguf")
        XCTAssertEqual(url.lastPathComponent, "model.gguf.part")
        XCTAssertEqual(url.deletingLastPathComponent().path, PathResolver.modelsDir.path)
    }
}
