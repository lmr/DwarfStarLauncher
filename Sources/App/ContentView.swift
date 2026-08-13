import SwiftUI

struct ContentView: View {
    @Environment(ServerManager.self) private var serverManager
    @Environment(StatusMonitor.self) private var statusMonitor
    @Environment(ModelManager.self) private var modelManager
    @Environment(AppErrorManager.self) private var appErrorManager
    // MARK: - Shell State (owned by ContentView)

    @State private var selectedTab: MainTab = .dashboard
    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Error banner (inline, replaces old alert-based error display)

            if let errorMessage = appErrorManager.errorMessage {
                ErrorBanner(message: errorMessage) {
                    appErrorManager.errorMessage = nil
                }
                .padding(.horizontal, DesignTokens.Spacing.s4)
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .opacity
                ))
            }

            // MARK: - Active Tab Content (Dashboard / Log / Downloads)
            //
            // Light inset from the title bar so scroll content doesn't sit
            // flush against the top edge.

            Group {
                switch selectedTab {
                case .dashboard:
                    DashboardView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .log:
                    LogView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .downloads:
                    DownloadsView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(.top, DesignTokens.Spacing.s3)

            // MARK: - Bottom Tab Bar (custom navigation with badges)

            BottomTabBar(selectedTab: $selectedTab)
                .padding(.horizontal, DesignTokens.Spacing.s4)
        }
        .background(DesignTokens.panelGradient)
        .toolbar {
            ToolbarItemGroup(placement: .principal) {
                TopChromeStrip()
            }
        }
        .onAppear {
            ensureDirectoriesExist()
        }
    }

    private func ensureDirectoriesExist() {
        let fm = FileManager.default
        let dirs = [
            PathResolver.binDir,
            PathResolver.modelsDir,
            PathResolver.metalDir,
            PathResolver.configRoot
        ]
        for dir in dirs {
            if !fm.fileExists(atPath: dir.path) {
                try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }
}
