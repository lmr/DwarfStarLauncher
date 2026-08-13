import XCTest
import Foundation
@testable import App

final class ServerConfigTests: XCTestCase {

    /// Builds a fully-populated config with a plain model path.
    private func makeBaseConfig() -> ServerConfig {
        var config = ServerConfig()
        config.modelPath = "/tmp/model.gguf"
        config.contextSize = 262144
        config.power = 100
        config.host = "0.0.0.0"
        config.port = 1234
        config.enableMtp = false
        config.ssdStreaming = false
        return config
    }

    func testBuildArgumentsWithoutMtpOrSsd() {
        let args = makeBaseConfig().buildArguments()
        XCTAssertEqual(args, [
            "--model", "/tmp/model.gguf",
            "--ctx", "262144",
            "--power", "100",
            "--host", "0.0.0.0",
            "--port", "1234"
        ])
    }

    func testBuildArgumentsIncludesMtpDraftForRegularPath() {
        var config = makeBaseConfig()
        config.enableMtp = true
        config.mtpModelPath = "/tmp/DeepSeek-V4-Flash-MTP.gguf"

        let args = config.buildArguments()
        XCTAssertTrue(args.contains("--mtp"))
        XCTAssertEqual(args[args.firstIndex(of: "--mtp")! + 1], "/tmp/DeepSeek-V4-Flash-MTP.gguf")
        XCTAssertTrue(args.contains("--mtp-draft"))
        XCTAssertEqual(args[args.firstIndex(of: "--mtp-draft")! + 1], "2")
    }

    func testBuildArgumentsUsesDsparkFlagsForDsparkPath() {
        var config = makeBaseConfig()
        config.enableMtp = true
        config.mtpModelPath = "/tmp/DSPARK-support.gguf"

        let args = config.buildArguments()
        XCTAssertTrue(args.contains("--dspark"))
        XCTAssertTrue(args.contains("--mtp"))
        XCTAssertEqual(args[args.firstIndex(of: "--mtp")! + 1], "/tmp/DSPARK-support.gguf")
        XCTAssertFalse(args.contains("--mtp-draft"))
    }

    func testBuildArgumentsIncludesSsdStreamingOptions() {
        var config = makeBaseConfig()
        config.ssdStreaming = true
        config.kvDiskPath = "/tmp/kv-dir"
        config.kvSpace = 8192

        let args = config.buildArguments()
        XCTAssertTrue(args.contains("--ssd-streaming"))
        XCTAssertEqual(args[args.firstIndex(of: "--kv-disk-dir")! + 1], "/tmp/kv-dir")
        XCTAssertEqual(args[args.firstIndex(of: "--kv-disk-space-mb")! + 1], "8192")
    }

    func testBuildArgumentsOmitsKvDiskPathWhenNil() {
        var config = makeBaseConfig()
        config.ssdStreaming = true
        config.kvDiskPath = nil
        config.kvSpace = 4096

        let args = config.buildArguments()
        XCTAssertTrue(args.contains("--ssd-streaming"))
        XCTAssertFalse(args.contains("--kv-disk-dir"))
        XCTAssertTrue(args.contains("--kv-disk-space-mb"))
    }
}
