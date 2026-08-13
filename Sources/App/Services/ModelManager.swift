import Foundation
import SwiftUI

@Observable
final class ModelManager {
    var models: [GGUFModel] = []
    var mtpModels: [GGUFModel] = []
    var selectedModel: GGUFModel? = nil
    var selectedMtpModel: GGUFModel? = nil
    var isRefreshing = false

    func refresh() {
        isRefreshing = true
        defer { isRefreshing = false }

        let modelsDir = PathResolver.modelsDir
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: modelsDir.path) else {
            models = []
            return
        }

        do {
            let contents = try fileManager.contentsOfDirectory(at: modelsDir, includingPropertiesForKeys: [.fileSizeKey])
            let ggufFiles = contents.filter { $0.pathExtension == "gguf" || $0.lastPathComponent.hasSuffix(".gguf") }

            let mtp = ggufFiles.filter { $0.lastPathComponent.localizedStandardContains("mtp") || $0.lastPathComponent.localizedStandardContains("dspark")  }
            let main = ggufFiles.filter { !$0.lastPathComponent.localizedStandardContains("mtp") && !$0.lastPathComponent.localizedStandardContains("dspark") }
            mtpModels = mtp.compactMap { url in
                let resources = try? url.resourceValues(forKeys: [.fileSizeKey])
                return GGUFModel(
                    path: url.path,
                    name: url.lastPathComponent,
                    size: Int64(resources?.fileSize ?? 0)
                )
            }.sorted { $0.size > $1.size }
            models = main.compactMap { url in
                let resources = try? url.resourceValues(forKeys: [.fileSizeKey])
                return GGUFModel(
                    path: url.path,
                    name: url.lastPathComponent,
                    size: Int64(resources?.fileSize ?? 0)
                )
            }.sorted { $0.size > $1.size }
        } catch {
            models = []
        }
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

    func selectModel(byPath path: String) {
        let normalized = Self.normalizedPath(path)
        guard let model = models.first(where: { Self.normalizedPath($0.path) == normalized }) else { return }
        selectModel(model)
    }
}
