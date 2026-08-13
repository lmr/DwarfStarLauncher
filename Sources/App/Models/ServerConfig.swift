import Foundation

struct ServerConfig: Codable, Equatable {
    var modelPath: String = ""
    var hfToken: String?
    var mtpModelPath: String = "\(NSHomeDirectory())/.ds4-launcher/models/DeepSeek-V4-Flash-MTP-Q4K-Q8_0-F32.gguf"
    var enableMtp: Bool = true
    var contextSize: Int = 262144
    var power: Int = 100
    var host: String = "0.0.0.0"
    var port: Int = 1234
    var kvSpace: Int = 8192
    var ssdStreaming: Bool = false
    var kvDiskPath: String?
    var importPath: String?

    func buildArguments() -> [String] {
        var args: [String] = []
        args.append(contentsOf: ["--model", modelPath])
        args.append(contentsOf: ["--ctx", String(contextSize)])
        args.append(contentsOf: ["--power", String(power)])
        if enableMtp {
            if mtpModelPath.localizedStandardContains("dspark") {
                args.append(contentsOf: ["--dspark", "--mtp", mtpModelPath])
            } else {
                args.append(contentsOf: ["--mtp", mtpModelPath, "--mtp-draft", "2"])
            }
        }

        args.append(contentsOf: ["--host", host])
        args.append(contentsOf: ["--port", String(port)])

        if ssdStreaming {
            args.append("--ssd-streaming")
            if let kvDiskPath {
                args.append(contentsOf: ["--kv-disk-dir", kvDiskPath])
            }
            if kvSpace > 0 {
                args.append(contentsOf: ["--kv-disk-space-mb", String(kvSpace)])
            }
        }

        return args
    }
}
