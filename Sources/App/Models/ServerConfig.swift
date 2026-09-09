import Foundation

struct ServerConfig: Codable, Equatable {
    var modelPath: String = ""
    /// Optional vision sidecar GGUF passed to ds4-server as `--vision`.
    /// This is intentionally independent from the main model and MTP paths.
    var visionEncoderPath: String?
    var enableVision: Bool = false
    var hfToken: String?
    var mtpModelPath: String = "\(NSHomeDirectory())/.ds4-launcher/models/DeepSeek-V4-Flash-MTP-Q4K-Q8_0-F32.gguf"
    var enableMtp: Bool = true
    /// Enables model-embedded MTP with ds4's boolean `--mtp` flag (used by
    /// Qwen3.8-Flash-Next), rather than loading an external support GGUF.
    var useEmbeddedMtp: Bool = false
    var contextSize: Int = 262144
    var power: Int = 100
    var host: String = "127.0.0.1"
    var port: Int = 1234
    var kvSpace: Int = 8192
    var ssdStreaming: Bool = false
    var kvDiskPath: String?
    var importPath: String?
    var serverBinaryPath: String?

    private enum CodingKeys: String, CodingKey {
        case modelPath, visionEncoderPath, enableVision, hfToken
        case mtpModelPath, enableMtp, useEmbeddedMtp, contextSize, power
        case host, port, kvSpace, ssdStreaming, kvDiskPath, importPath
        case serverBinaryPath
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        modelPath = try container.decodeIfPresent(String.self, forKey: .modelPath) ?? ""
        visionEncoderPath = try container.decodeIfPresent(String.self, forKey: .visionEncoderPath)
        enableVision = try container.decodeIfPresent(Bool.self, forKey: .enableVision) ?? false
        hfToken = try container.decodeIfPresent(String.self, forKey: .hfToken)
        mtpModelPath = try container.decodeIfPresent(String.self, forKey: .mtpModelPath)
            ?? "\(NSHomeDirectory())/.ds4-launcher/models/DeepSeek-V4-Flash-MTP-Q4K-Q8_0-F32.gguf"
        enableMtp = try container.decodeIfPresent(Bool.self, forKey: .enableMtp) ?? true
        useEmbeddedMtp = try container.decodeIfPresent(Bool.self, forKey: .useEmbeddedMtp) ?? false
        contextSize = try container.decodeIfPresent(Int.self, forKey: .contextSize) ?? 262144
        power = try container.decodeIfPresent(Int.self, forKey: .power) ?? 100
        host = try container.decodeIfPresent(String.self, forKey: .host) ?? "127.0.0.1"
        port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 1234
        kvSpace = try container.decodeIfPresent(Int.self, forKey: .kvSpace) ?? 8192
        ssdStreaming = try container.decodeIfPresent(Bool.self, forKey: .ssdStreaming) ?? false
        kvDiskPath = try container.decodeIfPresent(String.self, forKey: .kvDiskPath)
        importPath = try container.decodeIfPresent(String.self, forKey: .importPath)
        serverBinaryPath = try container.decodeIfPresent(String.self, forKey: .serverBinaryPath)
    }

    func buildArguments() -> [String] {
        var args: [String] = []
        args.append(contentsOf: ["--model", modelPath])
        if enableVision,
           let path = visionEncoderPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty {
            args.append(contentsOf: ["--vision", path])
        }
        args.append(contentsOf: ["--ctx", String(contextSize)])
        args.append(contentsOf: ["--power", String(power)])
        if useEmbeddedMtp {
            // Qwen3.8's MTP weights live in the main GGUF. This setting is
            // intentionally independent from the external-MTP toggle/path.
            args.append("--mtp")
        } else if enableMtp {
            if mtpModelPath.localizedStandardContains("dspark") {
                args.append(contentsOf: ["--dspark", "--mtp-model", mtpModelPath])
            } else {
                args.append(contentsOf: ["--mtp-model", mtpModelPath, "--mtp-draft", "2"])
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
