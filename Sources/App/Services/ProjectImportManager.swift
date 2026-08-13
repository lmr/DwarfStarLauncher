import Foundation
import SwiftUI

@Observable
final class ProjectImportManager {
    var importPath: String? = nil
    var lastImportDate: Date? = nil
    var isImporting = false
    var statusMessage: String? = nil
    var alertMessage: String? = nil

    private let binaries = ["ds4", "ds4-agent", "ds4-bench", "ds4-eval", "ds4-server"]

    init() {
        loadImportPathFromConfig()
    }

    // MARK: - Validation

    func validateProject(at url: URL) -> Bool {
        let fm = FileManager.default
        let metalDir = url.appendingPathComponent("metal")
        let serverBinary = url.appendingPathComponent("ds4-server")

        var metalIsDir = ObjCBool(false)
        let metalExists = fm.fileExists(atPath: metalDir.path, isDirectory: &metalIsDir)
        guard metalExists && metalIsDir.boolValue else {
            alertMessage = "Selected directory does not contain a valid DS4 project.\nMissing: metal/ directory."
            return false
        }

        guard fm.isExecutableFile(atPath: serverBinary.path) else {
            alertMessage = "Selected directory does not contain a valid DS4 project.\nMissing: ds4-server (executable)."
            return false
        }

        return true
    }

    // MARK: - Import

    func importFrom(url: URL) {
        guard validateProject(at: url) else { return }

        isImporting = true
        statusMessage = "Copying files..."

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let fm = FileManager.default

            // Copy metal/ directory (remove-and-replace)
            let sourceMetal = url.appendingPathComponent("metal")
            let destMetal = PathResolver.metalDir
            try? fm.removeItem(at: destMetal)
            do {
                try fm.copyItem(at: sourceMetal, to: destMetal)
            } catch {
                DispatchQueue.main.async {
                    self.isImporting = false
                    self.statusMessage = "Import failed: \(error.localizedDescription)"
                }
                return
            }

            // Copy binaries individually
            let binDir = PathResolver.binDir
            for binary in binaries {
                let source = url.appendingPathComponent(binary)
                let dest = binDir.appendingPathComponent(binary)
                try? fm.removeItem(at: dest)
                do {
                    try fm.copyItem(at: source, to: dest)
                } catch {
                    DispatchQueue.main.async {
                        self.isImporting = false
                        self.statusMessage = "Import failed: \(error.localizedDescription)"
                    }
                    return
                }
            }

            DispatchQueue.main.async {
                self.importPath = url.path
                self.lastImportDate = Date()
                self.isImporting = false
                self.statusMessage = "Import complete"
                self.persistImportPath()
            }
        }
    }

    // MARK: - Refresh

    func refresh() {
        guard let path = importPath else {
            alertMessage = "No import path saved. Please use Import Build first."
            return
        }

        let url = URL(fileURLWithPath: path)
        importFrom(url: url)
    }

    // MARK: - Change Path

    func changePath() {
        // This is handled in the UI layer — this method clears so the UI
        // knows to present the picker again on next Import tap.
        importPath = nil
    }

    // MARK: - Persistence

    private func loadImportPathFromConfig() {
        let file = PathResolver.configFile
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        guard let data = try? Data(contentsOf: file) else { return }
        guard let decoded = try? JSONDecoder().decode(ServerConfig.self, from: data) else { return }
        importPath = decoded.importPath
    }

    private func persistImportPath() {
        let file = PathResolver.configFile
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        guard let data = try? Data(contentsOf: file) else { return }
        guard var config = try? JSONDecoder().decode(ServerConfig.self, from: data) else { return }
        config.importPath = importPath
        guard let newData = try? JSONEncoder().encode(config) else { return }
        try? newData.write(to: file, options: .atomic)
    }
}
