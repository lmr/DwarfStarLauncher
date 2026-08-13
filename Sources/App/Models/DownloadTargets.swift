import Foundation

// MARK: - DownloadTarget

enum DownloadTarget: String, CaseIterable, Identifiable, Equatable {
    // DeepSeek Flash (5 targets)
    case ds4fQ2 = "ds4f-q2"
    case ds4fQ2Q4 = "ds4f-q2q4"
    case ds4fQ4 = "ds4f-q4"
    case ds4fMxfp4 = "ds4f-mxfp4"
    case ds4fDspark = "ds4f-dspark"

    // PRO (4 targets)
    case proQ2Imatrix = "pro-q2-imatrix"
    case proQ4Layers00_30 = "pro-q4-layers00-30"
    case proQ4Layers31Output = "pro-q4-layers31-output"
    case proQ4Split = "pro-q4-split"

    // GLM Unsloth (1 target)
    case glmUnslothQ4 = "glm-unsloth-q4"

    // GLM Antirez (3 targets)
    case glmAntirezIQ2XXS = "glm-antirez-iq2xxs"
    case glmAntirezQ2 = "glm-antirez-q2"
    case glmAntirezQ4 = "glm-antirez-q4"

    var id: String { rawValue }

    var category: DownloadCategory {
        switch self {
        case .ds4fQ2, .ds4fQ2Q4, .ds4fQ4, .ds4fMxfp4, .ds4fDspark:
            return .deepSeekFlash
        case .proQ2Imatrix, .proQ4Layers00_30, .proQ4Layers31Output, .proQ4Split:
            return .proModels
        case .glmUnslothQ4:
            return .glmModels
        case .glmAntirezIQ2XXS, .glmAntirezQ2, .glmAntirezQ4:
            return .glmModels
        }
    }

    var repo: String {
        switch self {
        case .ds4fQ2, .ds4fQ2Q4, .ds4fQ4, .ds4fMxfp4, .ds4fDspark,
             .proQ2Imatrix, .proQ4Layers00_30, .proQ4Layers31Output, .proQ4Split:
            return "antirez/deepseek-v4-gguf"
        case .glmUnslothQ4:
            return "unsloth/GLM-5.2-GGUF"
        case .glmAntirezIQ2XXS, .glmAntirezQ2, .glmAntirezQ4:
            return "antirez/GLM-5.2-GGUF"
        }
    }

    var files: [ModelFile] {
        switch self {
        case .ds4fQ2:
            return [ModelFile(remoteName: "DeepSeek-V4-Flash-IQ2XXS-w2Q2K-AProjQ8-SExpQ8-OutQ8-chat-v2-imatrix-0731.gguf", localName: "DeepSeek-V4-Flash-IQ2XXS-w2Q2K-AProjQ8-SExpQ8-OutQ8-chat-v2-imatrix-0731.gguf", downloaded: false, size: 86_720_111_488)]
        case .ds4fQ2Q4:
            return [ModelFile(remoteName: "DeepSeek-V4-Flash-Layers37-42Q4KExperts-OtherExpertLayersIQ2XXSGateUp-Q2KDown-AProjQ8-SExpQ8-OutQ8-chat-v2-imatrix-fixed-0731.gguf", localName: "DeepSeek-V4-Flash-Layers37-42Q4KExperts-OtherExpertLayersIQ2XXSGateUp-Q2KDown-AProjQ8-SExpQ8-OutQ8-chat-v2-imatrix-fixed-0731.gguf", downloaded: false, size: 97_591_747_456)]
        case .ds4fQ4:
            return [ModelFile(remoteName: "DeepSeek-V4-Flash-Q4KExperts-F16HC-F16Compressor-F16Indexer-Q8Attn-Q8Shared-Q8Out-chat-v2-imatrix-0731.gguf", localName: "DeepSeek-V4-Flash-Q4KExperts-F16HC-F16Compressor-F16Indexer-Q8Attn-Q8Shared-Q8Out-chat-v2-imatrix-0731.gguf", downloaded: false, size: 164_633_502_592)]
        case .ds4fMxfp4:
            return [ModelFile(remoteName: "DeepSeek-V4-Flash-MXFP4Experts-F16HC-F16Compressor-F16Indexer-Q8Attn-Q8Shared-Q8Out-chat-v2-mxfp4-0731.gguf", localName: "DeepSeek-V4-Flash-MXFP4Experts-F16HC-F16Compressor-F16Indexer-Q8Attn-Q8Shared-Q8Out-chat-v2-mxfp4-0731.gguf", downloaded: false, size: 155_976_458_848)]
        case .ds4fDspark:
            return [ModelFile(remoteName: "DeepSeek-V4-Flash-DSpark-support-0731.gguf", localName: "DeepSeek-V4-Flash-DSpark-support-0731.gguf", downloaded: false, size: 5_989_114_272)]
        case .proQ2Imatrix:
            return [ModelFile(remoteName: "DeepSeek-V4-Pro-IQ2XXS-w2Q2K-AProjQ8-SExpQ8-OutQ8-Instruct-imatrix.gguf", localName: "DeepSeek-V4-Pro-IQ2XXS-w2Q2K-AProjQ8-SExpQ8-OutQ8-Instruct-imatrix.gguf", downloaded: false, size: 464_627_334_560)]
        case .proQ4Layers00_30:
            return [ModelFile(remoteName: "DeepSeek-V4-Pro-Q4K-Layers00-30.gguf", localName: "DeepSeek-V4-Pro-Q4K-Layers00-30.gguf", downloaded: false, size: 457_521_327_328)]
        case .proQ4Layers31Output:
            return [ModelFile(remoteName: "DeepSeek-V4-Pro-Q4K-Layers-31-output.gguf", localName: "DeepSeek-V4-Pro-Q4K-Layers-31-output.gguf", downloaded: false, size: 441_962_533_120)]
        case .proQ4Split:
            return [
                ModelFile(remoteName: "DeepSeek-V4-Pro-Q4K-Layers00-30.gguf", localName: "DeepSeek-V4-Pro-Q4K-Layers00-30.gguf", downloaded: false, size: 457_521_327_328),
                ModelFile(remoteName: "DeepSeek-V4-Pro-Q4K-Layers-31-output.gguf", localName: "DeepSeek-V4-Pro-Q4K-Layers-31-output.gguf", downloaded: false, size: 441_962_533_120)
            ]
        case .glmUnslothQ4:
            let sizes: [Int64] = [
                9_423_744,
                49_433_942_336,
                48_566_415_136, 48_566_415_136, 48_566_415_136, 48_566_415_136,
                48_566_415_136, 48_566_415_136, 48_566_415_136, 48_566_415_136,
                29_314_424_736
            ]
            return (0..<11).map { i in
                let shard = String(format: "%05d", i + 1)
                let remote = "UD-Q4_K_XL/GLM-5.2-UD-Q4_K_XL-\(shard)-of-00011.gguf"
                let local = "GLM-5.2-UD-Q4_K_XL-\(shard)-of-00011.gguf"
                return ModelFile(remoteName: remote, localName: local, downloaded: false, size: sizes[i])
            }
        case .glmAntirezIQ2XXS:
            return [ModelFile(remoteName: "GLM-5.2-UD-IQ2_XXS_RoutedIQ2XXS_blk78Q2K.gguf", localName: "GLM-5.2-UD-IQ2_XXS_RoutedIQ2XXS_blk78Q2K.gguf", downloaded: false, size: 211_075_856_448)]
        case .glmAntirezQ2:
            return [ModelFile(remoteName: "GLM-5.2-UD-Q2_K_RoutedQ2K.gguf", localName: "GLM-5.2-UD-Q2_K_RoutedQ2K.gguf", downloaded: false, size: 262_036_650_048)]
        case .glmAntirezQ4:
            return [ModelFile(remoteName: "GLM-5.2-UD-Q4_K_RoutedQ4K.gguf", localName: "GLM-5.2-UD-Q4_K_RoutedQ4K.gguf", downloaded: false, size: 434_170_886_208)]
        }
    }

    var createsSymlink: Bool { false }

    var expectedTotalSize: Int64 {
        files.reduce(0) { $0 + $1.size }
    }

    var displayName: String {
        switch self {
        case .ds4fQ2:
            return "DeepSeek Flash Q2"
        case .ds4fQ2Q4:
            return "DeepSeek Flash Q2/Q4 Imatrix"
        case .ds4fQ4:
            return "DeepSeek Flash Q4 Imatrix"
        case .ds4fMxfp4:
            return "DeepSeek Flash MxFP4"
        case .ds4fDspark:
            return "DeepSeek Flash DSpark"
        case .proQ2Imatrix:
            return "PRO Q2 Imatrix"
        case .proQ4Layers00_30:
            return "PRO Q4 Layers 00-30"
        case .proQ4Layers31Output:
            return "PRO Q4 Layers 31-Output"
        case .proQ4Split:
            return "PRO Q4 Split (2 files)"
        case .glmUnslothQ4:
            return "GLM Unsloth Q4 (11 shards)"
        case .glmAntirezIQ2XXS:
            return "GLM Antirez IQ2XXS"
        case .glmAntirezQ2:
            return "GLM Antirez Q2"
        case .glmAntirezQ4:
            return "GLM Antirez Q4"
        }
    }

    var filename: String {
        // For backward compatibility with existing code
        files.first?.localName ?? rawValue
    }

    var expectedSize: Int64 {
        expectedTotalSize
    }

    var description: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let sizeStr = formatter.string(fromByteCount: expectedTotalSize)
        return "\(displayName) (\(sizeStr))"
    }

    var revision: String? { nil }

    var isDownloaded: Bool {
        !files.isEmpty && files.allSatisfy { file in
            let url = PathResolver.modelsDir.appendingPathComponent(file.localName)
            guard FileManager.default.fileExists(atPath: url.path),
                  let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = attrs[.size] as? Int64,
                  size == file.size else { return false }
            // Verify GGUF magic header for basic integrity (same check used post-download)
            guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
            defer { try? handle.close() }
            let data = handle.readData(ofLength: 4)
            guard data.count == 4, let magic = String(data: data, encoding: .utf8) else { return false }
            return ["GGUF", "GGML", "FGGU"].contains(magic)
        }
    }
}

// MARK: - DownloadCategory

enum DownloadCategory: String, CaseIterable, Identifiable, Hashable {
    case deepSeekFlash
    case proModels
    case glmModels

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .deepSeekFlash:
            return "DeepSeek Flash"
        case .proModels:
            return "PRO Models"
        case .glmModels:
            return "GLM Models"
        }
    }
}

// MARK: - ModelFile

struct ModelFile: Equatable {
    let remoteName: String
    let localName: String
    var downloaded: Bool
    let size: Int64

    init(remoteName: String, localName: String, downloaded: Bool, size: Int64) {
        self.remoteName = remoteName
        self.localName = localName
        self.downloaded = downloaded
        self.size = size
    }
}
