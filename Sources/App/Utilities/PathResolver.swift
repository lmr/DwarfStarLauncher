import Foundation
import SwiftUI

enum ModelStorageKind: String, CaseIterable {
    case main
    case mtp
    case vision
}

enum PathResolver {
    private static let defaults = UserDefaults.standard

    // MARK: - Roots

    static var dataRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ds4-launcher")
    }

    static var configRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/ds4-launcher")
    }

    static var binDir: URL {
        dataRoot.appendingPathComponent("bin")
    }

    /// The parent directory containing the main, MTP, and vision model
    /// subdirectories. Returns the user-selected location if set, otherwise
    /// falls back to `~/.ds4-launcher/models`.
    static var modelsDir: URL {
        let custom = defaults.string(forKey: "customModelsDirectory") ?? ""
        if custom.isEmpty {
            return defaultModelsDirectory
        }
        let url = URL(fileURLWithPath: custom, isDirectory: true)
        // Ensure the directory exists so FileManager checks in ModelManager / downloads succeed.
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        return url
    }

    /// Dedicated storage locations keep main models, MTP models, and vision
    /// encoders separate while sharing one user-configurable parent directory.
    static func modelsDirectory(for kind: ModelStorageKind) -> URL {
        let url = modelsDir.appendingPathComponent(kind.rawValue, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        return url
    }

    static var mainModelsDir: URL { modelsDirectory(for: .main) }
    static var mtpModelsDir: URL { modelsDirectory(for: .mtp) }
    static var visionModelsDir: URL { modelsDirectory(for: .vision) }

    static var hasCustomModelsDirectory: Bool {
        let custom = defaults.string(forKey: "customModelsDirectory") ?? ""
        return !custom.isEmpty && URL(fileURLWithPath: custom).path != defaultModelsDirectory.path
    }

    private static var defaultModelsDirectory: URL {
        dataRoot.appendingPathComponent("models")
    }

    /// Persist a user-chosen models directory. Pass nil to clear and reset to default.
    static func setCustomModelsDirectory(_ url: URL?) {
        defaults.set(url?.path ?? "", forKey: "customModelsDirectory")
    }

    /// Reset back to the built-in `~/.ds4-launcher/models` location.
    static func resetModelsDirectory() {
        defaults.removeObject(forKey: "customModelsDirectory")
    }

    // MARK: - Other paths (unchanged)

    static var metalDir: URL {
        dataRoot.appendingPathComponent("metal")
    }

    static var configFile: URL {
        configRoot.appendingPathComponent("config.json")
    }

    static var lifetimeMetricsFile: URL {
        dataRoot.appendingPathComponent("lifetime_metrics.json")
    }

    static var serverBinary: URL {
        binDir.appendingPathComponent("ds4-server")
    }

    static func partFileURL(for filename: String, in kind: ModelStorageKind = .main) -> URL {
        modelsDirectory(for: kind).appendingPathComponent("\(filename).part")
    }
}
