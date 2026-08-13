import SwiftUI
import AppKit
import os
import HuggingFaceDownloader

// MARK: - Environment Injection

extension View {
    func injectAppEnvironment(
        serverManager: ServerManager,
        statusMonitor: StatusMonitor,
        modelManager: ModelManager,
        modelDownloader: ModelDownloader,
        projectImportManager: ProjectImportManager,
        appErrorManager: AppErrorManager
    ) -> some View {
        self
            .environment(serverManager)
            .environment(statusMonitor)
            .environment(modelManager)
            .environment(modelDownloader)
            .environment(projectImportManager)
            .environment(appErrorManager)
    }
}

// MARK: - Main App

@main
struct DwarfStarLauncherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("DwarfStarLauncher", id: "main") {
            rootContent(ContentView())
                .frame(minWidth: 800, minHeight: 600)
        }
        .windowResizability(.contentMinSize)

        Settings {
            rootContent(ConfigOverlayView())
                .frame(minWidth: 680, minHeight: 480)
        }

        MenuBarExtra {
            rootContent(TrayMenu())
        } label: {
            rootContent(TrayTitleLabel())
        }
    }

    @ViewBuilder
    private func rootContent<V: View>(_ content: V) -> some View {
        content.injectAppEnvironment(
            serverManager: AppDelegate.sharedServerManager,
            statusMonitor: AppDelegate.sharedStatusMonitor,
            modelManager: AppDelegate.sharedModelManager,
            modelDownloader: AppDelegate.sharedModelDownloader,
            projectImportManager: AppDelegate.sharedProjectImportManager,
            appErrorManager: AppDelegate.sharedAppErrorManager
        )
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    static let sharedStatusMonitor = StatusMonitor()
    static let sharedServerManager = ServerManager(statusMonitor: sharedStatusMonitor)
    static let sharedModelManager = ModelManager()
    static let sharedModelDownloader = ModelDownloader()
    static let sharedProjectImportManager = ProjectImportManager()
    static let sharedAppErrorManager = AppErrorManager()

    var serverManager: ServerManager { Self.sharedServerManager }
    var statusMonitor: StatusMonitor { Self.sharedStatusMonitor }
    var modelManager: ModelManager { Self.sharedModelManager }
    var modelDownloader: ModelDownloader { Self.sharedModelDownloader }
    var projectImportManager: ProjectImportManager { Self.sharedProjectImportManager }
    var appErrorManager: AppErrorManager { Self.sharedAppErrorManager }

    override init() {
        super.init()
        configureDownloadCallbacks()
        // Warm the in-memory token cache so downloads don't trigger a disk read
        // while a request is being built.
        _ = ConfigTokenStore().load()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Managers are initialized as static properties above.
    }

    func applicationWillTerminate(_ notification: Notification) {
        Self.sharedServerManager.stopSynchronously()
        Self.sharedStatusMonitor.stopTimer()
        Self.sharedModelDownloader.cancel()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    private func configureDownloadCallbacks() {
        modelDownloader.onDownloadComplete = { [weak self] target in
            guard let self else { return }
            DispatchQueue.main.async {
                self.handleDownloadCompletion(of: target)
            }
        }

        modelDownloader.onDownloadError = { [weak self] message in
            guard let self else { return }
            DispatchQueue.main.async {
                self.handleDownloadError(message)
            }
        }
    }

    /// Coordinates download-completion effects. Each effect is an explicit,
    /// separable step that mutates exactly one manager — no single closure
    /// reaches into `ModelManager`, `ServerManager.config`, and
    /// `AppErrorManager` at once.
    private func handleDownloadCompletion(of target: DownloadTarget) {
        // Effect 1 — refresh the model list so the completed file appears.
        Self.sharedModelManager.refresh()

        // Effect 2 — wire the downloaded model into selection and the server
        // config, but only when the download is a selectable model file inside
        // the models directory. Shard/split targets and files outside the
        // models dir are not selectable model paths.
        guard let modelPath = Self.selectableModelPath(for: target) else { return }
        Self.sharedServerManager.config.modelPath = modelPath
        Self.sharedModelManager.selectModel(byPath: modelPath)
    }

    private func handleDownloadError(_ message: String) {
        Self.sharedAppErrorManager.errorMessage = message
    }

    /// Side-effect-free decision: the model path a completed download maps to,
    /// or `nil` when the download is not a selectable single model file inside
    /// the models directory. Explicit and testable, not a silent guard inside
    /// a fan-out closure.
    private static func selectableModelPath(for target: DownloadTarget) -> String? {
        guard let firstFile = target.files.first else { return nil }

        switch target {
        case .proQ4Split, .glmUnslothQ4:
            // Multi-shard bundles are not a single selectable model path.
            return nil
        default:
            break
        }

        let resolvedURL = PathResolver.modelsDir.appendingPathComponent(firstFile.localName)
        let canonicalResolvedURL = resolvedURL.resolvingSymlinksInPath()
        let canonicalModelsDir = PathResolver.modelsDir.resolvingSymlinksInPath()
        guard canonicalResolvedURL.path == canonicalModelsDir.path
                || canonicalResolvedURL.path.hasPrefix(canonicalModelsDir.path + "/") else {
            return nil
        }
        return resolvedURL.path
    }
}
