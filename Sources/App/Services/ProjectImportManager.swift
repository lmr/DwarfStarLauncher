import Foundation
import SwiftUI
import HuggingFaceDownloader

private struct ImportArtifact {
    let stagedURL: URL
    let destinationURL: URL
    let backupURL: URL
}

private enum ProjectImportError: LocalizedError {
    case invalidProject(String)
    case replacementFailed(String)
    case rollbackFailed(String, details: [String], recoveryLocation: String)

    var errorDescription: String? {
        switch self {
        case .invalidProject(let message):
            return "Selected directory does not contain a valid DS4 project.\n\(message)"
        case .replacementFailed(let message):
            return "Import failed while replacing the current build: \(message). The previous files were restored."
        case .rollbackFailed(let message, let details, let recoveryLocation):
            return "Import failed while replacing the current build: \(message). " +
                "Rollback was incomplete (\(details.joined(separator: "; "))). " +
                "Recovery files were kept at \(recoveryLocation)."
        }
    }
}

@Observable
final class ProjectImportManager {
    var importPath: String? = nil
    var lastImportDate: Date? = nil
    var isImporting = false
    var statusMessage: String? = nil
    var alertMessage: String? = nil

    private let binaries = ["ds4", "ds4-agent", "ds4-bench", "ds4-eval", "ds4-server"]
    private let configStore: ConfigStore
    private let dataRoot: URL

    private var metalDirectory: URL {
        dataRoot.appendingPathComponent("metal", isDirectory: true)
    }

    private var binDirectory: URL {
        dataRoot.appendingPathComponent("bin", isDirectory: true)
    }

    init(
        configStore: ConfigStore = ConfigStore(),
        dataRoot: URL = PathResolver.dataRoot
    ) {
        self.configStore = configStore
        self.dataRoot = dataRoot
        loadImportPathFromConfig()
    }

    // MARK: - Validation

    func validateProject(at url: URL) -> Bool {
        guard let issue = validationIssue(at: url) else { return true }
        alertMessage = "Selected directory does not contain a valid DS4 project.\n\(issue)"
        return false
    }

    private func validationIssue(at url: URL) -> String? {
        let fm = FileManager.default
        let metalDir = url.appendingPathComponent("metal", isDirectory: true)
        var metalIsDirectory = ObjCBool(false)
        guard fm.fileExists(atPath: metalDir.path, isDirectory: &metalIsDirectory), metalIsDirectory.boolValue else {
            return "Missing: metal/ directory."
        }

        for binary in binaries {
            let binaryURL = url.appendingPathComponent(binary)
            var isDirectory = ObjCBool(false)
            guard fm.fileExists(atPath: binaryURL.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
                return "Missing: \(binary) binary."
            }
            guard fm.isExecutableFile(atPath: binaryURL.path) else {
                return "Not executable: \(binary)."
            }
        }

        return nil
    }

    // MARK: - Import

    func importFrom(url: URL) {
        guard validateProject(at: url) else { return }

        isImporting = true
        statusMessage = "Copying files..."

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                try installProject(at: url)
                DispatchQueue.main.async {
                    self.importPath = url.path
                    self.lastImportDate = Date()
                    self.isImporting = false
                    self.statusMessage = "Import complete"
                    self.persistImportPath()
                }
            } catch {
                DispatchQueue.main.async {
                    self.isImporting = false
                    self.statusMessage = "Import failed: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Stages every source artifact first, then replaces the installed files
    /// with rollback support if any step in the replacement phase fails.
    func installProject(at url: URL) throws {
        if let issue = validationIssue(at: url) {
            throw ProjectImportError.invalidProject(issue)
        }

        let fm = FileManager.default
        try fm.createDirectory(at: dataRoot, withIntermediateDirectories: true)

        let stagingRoot = dataRoot.appendingPathComponent(
            ".ds4-import-\(UUID().uuidString)",
            isDirectory: true
        )
        try fm.createDirectory(at: stagingRoot, withIntermediateDirectories: false)
        var preserveStagingForRecovery = false
        defer {
            if !preserveStagingForRecovery {
                try? fm.removeItem(at: stagingRoot)
            }
        }

        let stagedMetal = stagingRoot.appendingPathComponent("metal", isDirectory: true)
        let stagedBin = stagingRoot.appendingPathComponent("bin", isDirectory: true)
        try fm.copyItem(at: url.appendingPathComponent("metal", isDirectory: true), to: stagedMetal)
        try fm.createDirectory(at: stagedBin, withIntermediateDirectories: true)

        var artifacts = [
            ImportArtifact(
                stagedURL: stagedMetal,
                destinationURL: metalDirectory,
                backupURL: stagingRoot.appendingPathComponent("backup/metal", isDirectory: true)
            )
        ]
        for binary in binaries {
            let stagedURL = stagedBin.appendingPathComponent(binary)
            try fm.copyItem(at: url.appendingPathComponent(binary), to: stagedURL)
            artifacts.append(
                ImportArtifact(
                    stagedURL: stagedURL,
                    destinationURL: binDirectory.appendingPathComponent(binary),
                    backupURL: stagingRoot.appendingPathComponent("backup/bin/\(binary)")
                )
            )
        }

        try fm.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        try fm.createDirectory(
            at: stagingRoot.appendingPathComponent("backup/bin", isDirectory: true),
            withIntermediateDirectories: true
        )
        try replaceArtifacts(
            artifacts,
            fileManager: fm,
            stagingRoot: stagingRoot,
            preserveStagingForRecovery: &preserveStagingForRecovery
        )
    }

    private func replaceArtifacts(
        _ artifacts: [ImportArtifact],
        fileManager fm: FileManager,
        stagingRoot: URL,
        preserveStagingForRecovery: inout Bool
    ) throws {
        var backedUp: [(destination: URL, backup: URL)] = []
        var installed: [URL] = []

        do {
            for artifact in artifacts {
                if fm.fileExists(atPath: artifact.destinationURL.path) {
                    try fm.moveItem(at: artifact.destinationURL, to: artifact.backupURL)
                    backedUp.append((artifact.destinationURL, artifact.backupURL))
                }

                try fm.moveItem(at: artifact.stagedURL, to: artifact.destinationURL)
                installed.append(artifact.destinationURL)
            }
        } catch {
            let replacementError = error.localizedDescription
            var rollbackErrors: [String] = []

            for destination in installed.reversed() {
                do {
                    if fm.fileExists(atPath: destination.path) {
                        try fm.removeItem(at: destination)
                    }
                } catch {
                    rollbackErrors.append("could not remove \(destination.path): \(error.localizedDescription)")
                }
            }

            for item in backedUp.reversed() {
                do {
                    if fm.fileExists(atPath: item.destination.path) {
                        try fm.removeItem(at: item.destination)
                    }
                    try fm.moveItem(at: item.backup, to: item.destination)
                } catch {
                    rollbackErrors.append("could not restore \(item.destination.path): \(error.localizedDescription)")
                }
            }

            if rollbackErrors.isEmpty {
                throw ProjectImportError.replacementFailed(replacementError)
            }

            preserveStagingForRecovery = true
            throw ProjectImportError.rollbackFailed(
                replacementError,
                details: rollbackErrors,
                recoveryLocation: stagingRoot.path
            )
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
        persistImportPath()
    }

    // MARK: - Persistence

    private func loadImportPathFromConfig() {
        importPath = configStore.load(ServerConfig.self)?.importPath
    }

    private func persistImportPath() {
        do {
            try configStore.updateJSONObject { object in
                if let importPath {
                    object["importPath"] = importPath
                } else {
                    object.removeValue(forKey: "importPath")
                }
            }
        } catch {
            alertMessage = "Failed to save import path: \(error.localizedDescription)"
        }
    }
}
