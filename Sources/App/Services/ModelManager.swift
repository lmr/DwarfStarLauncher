import Foundation
import SwiftUI

@Observable
final class ModelManager {
    var models: [GGUFModel] = []
    var mtpModels: [GGUFModel] = []
    var visionModels: [GGUFModel] = []
    var selectedModel: GGUFModel? = nil
    var selectedMtpModel: GGUFModel? = nil
    var selectedVisionModel: GGUFModel? = nil
    var isRefreshing = false

    func refresh() {
        isRefreshing = true
        defer { isRefreshing = false }

        let modelsDir = PathResolver.modelsDir
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: modelsDir.path) else {
            models = []
            mtpModels = []
            visionModels = []
            return
        }

        do {
            let legacyContents = try fileManager.contentsOfDirectory(
                at: modelsDir,
                includingPropertiesForKeys: [.fileSizeKey]
            )
            let legacyGGUF = legacyContents.filter { isGGUFFile($0) }

            // Files already in a dedicated directory are classified by their
            // location. Root-level files use the legacy filename convention so
            // existing installations remain visible without a risky migration.
            let vision = files(in: PathResolver.visionModelsDir)
                + legacyGGUF.filter { isVisionEncoderFilename($0.lastPathComponent) }
            let mtp = files(in: PathResolver.mtpModelsDir)
                + legacyGGUF.filter {
                    !isVisionEncoderFilename($0.lastPathComponent)
                        && ($0.lastPathComponent.localizedStandardContains("mtp")
                            || $0.lastPathComponent.localizedStandardContains("dspark"))
                }
            let main = files(in: PathResolver.mainModelsDir)
                + legacyGGUF.filter {
                    !isVisionEncoderFilename($0.lastPathComponent)
                        && !$0.lastPathComponent.localizedStandardContains("mtp")
                        && !$0.lastPathComponent.localizedStandardContains("dspark")
                }

            func makeModels(from urls: [URL]) -> [GGUFModel] {
                urls.compactMap { url in
                    let resources = try? url.resourceValues(forKeys: [.fileSizeKey])
                    return GGUFModel(
                        path: url.path,
                        name: url.lastPathComponent,
                        size: Int64(resources?.fileSize ?? 0)
                    )
                }.sorted { $0.size > $1.size }
            }

            visionModels = makeModels(from: vision)
            mtpModels = makeModels(from: mtp)
            models = makeModels(from: main)
        } catch {
            models = []
            mtpModels = []
            visionModels = []
        }
    }

    private func files(in directory: URL) -> [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else {
            return []
        }
        return contents.filter { isGGUFFile($0) }
    }

    private func isGGUFFile(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "gguf"
            || url.lastPathComponent.lowercased().hasSuffix(".gguf")
    }

    private func isVisionEncoderFilename(_ filename: String) -> Bool {
        filename.localizedStandardContains("vision-encoder")
    }

    func selectModel(_ model: GGUFModel) {
        selectedModel = model
        for i in models.indices {
            models[i].isSelected = models[i].id == model.id
        }
    }

    func selectMtpModel(_ model: GGUFModel) {
        selectedMtpModel = model
        for i in mtpModels.indices {
            mtpModels[i].isSelected = mtpModels[i].id == model.id
        }
    }

    func selectVisionModel(_ model: GGUFModel) {
        selectedVisionModel = model
        for i in visionModels.indices {
            visionModels[i].isSelected = visionModels[i].id == model.id
        }
    }

    /// Normalizes a filesystem path so identity comparisons are robust to
    /// symlink/real-path representation differences (e.g. `/var` vs `/private/var`).
    private static func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    func selectMtpModel(byPath path: String) {
        let normalized = Self.normalizedPath(path)
        guard let model = mtpModels.first(where: { Self.normalizedPath($0.path) == normalized }) else { return }
        selectMtpModel(model)
    }

    func selectVisionModel(byPath path: String) {
        let normalized = Self.normalizedPath(path)
        guard let model = visionModels.first(where: { Self.normalizedPath($0.path) == normalized }) else { return }
        selectVisionModel(model)
    }

    func selectModel(byPath path: String) {
        let normalized = Self.normalizedPath(path)
        guard let model = models.first(where: { Self.normalizedPath($0.path) == normalized }) else { return }
        selectModel(model)
    }
}
