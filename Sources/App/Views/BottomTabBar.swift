import SwiftUI

/// Tab navigation enum for the bottom tab bar.
enum MainTab: Int, CaseIterable, Identifiable {
    case dashboard
    case log
    case downloads

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .log:       return "Log"
        case .downloads: return "Downloads"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .log:       return "doc.text"
        case .downloads: return "arrow.down.circle"
        }
    }
}

struct BottomTabBar: View {
    @Environment(ServerManager.self) private var serverManager
    @Environment(ModelDownloader.self) private var modelDownloader

    @Binding var selectedTab: MainTab


    // MARK: - Badge computation

    /// Numeric in-flight badge count on Dashboard / Downloads tabs.
    private var dashboardBadgeCount: Int {
        guard serverManager.status == .running || serverManager.status == .starting else { return 0 }
        return serverManager.status == .running ? 1 : 0
    }

    private var downloadsBadgeCount: Int {
        guard case .progress = modelDownloader.downloadState else { return 0 }
        return 1 // Single in-flight download indicator (could be extended to count targets)
    }

    /// Danger dot on Log tab when server is in error state.
    private var logHasError: Bool {
        if case .error = serverManager.status { return true }
        return false
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MainTab.allCases) { tab in
                VStack(spacing: DesignTokens.Spacing.s1) {
                    ZStack(alignment: .bottomTrailing) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: DesignTokens.Height.tabIconSize))
                            .foregroundStyle(selectedTab == tab ? Color.accentColor : DesignTokens.typeSecondary)
                            .scaleEffect(selectedTab == tab ? 1.0 : 0.95)

                        if selectedTab == tab {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 6, height: 6)
                                .offset(x: 8, y: -4)
                                .transition(.scale.combined(with: .opacity))
                        } else {
                            Circle()
                                .fill(Color.clear)
                                .frame(width: 6, height: 6)
                                .offset(x: 8, y: -4)
                        }

                        let badge = badgeCount(for: tab)
                        if badge > 0 && tab != .log {
                            Text("\(badge)")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(DesignTokens.danger))
                                .offset(x: 10, y: -6)
                        }

                        if logHasError && tab == .log {
                            Circle()
                                .fill(DesignTokens.danger)
                                .frame(width: 8, height: 8)
                                .offset(x: 12, y: -4)
                        }
                    }

                    Text(tab.title)
                        .font(.subheadline)
                        .foregroundStyle(selectedTab == tab ? Color.accentColor : DesignTokens.typeSecondary)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        selectedTab = tab
                    }
                }

                if tab != MainTab.allCases.last {
                    Divider()
                        .frame(width: 1)
                        .background(DesignTokens.separator)
                }
            }

            Divider()
                .frame(width: 1)
                .background(DesignTokens.separator)

            SettingsLink {
                VStack(spacing: DesignTokens.Spacing.s1) {
                    Image(systemName: "gearshape")
                        .font(.system(size: DesignTokens.Height.tabIconSize))
                        .foregroundStyle(DesignTokens.typeSecondary)

                    Text("Settings")
                        .font(.subheadline)
                        .foregroundStyle(DesignTokens.typeSecondary)
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .help("Settings (⌘+,)")
        }
        .padding(.horizontal, DesignTokens.Spacing.s4)
        .padding(.vertical, DesignTokens.Spacing.s1)
        .frame(maxHeight: DesignTokens.Height.bottomTabBarMax)
        .background(DesignTokens.cardSurface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(DesignTokens.separatorStrong, lineWidth: 1)
        )
        .shadow(
            color: DesignTokens.Elevation.low.color,
            radius: DesignTokens.Elevation.low.y,
            x: DesignTokens.Elevation.low.x,
            y: DesignTokens.Elevation.low.y
        )
    }

    private func badgeCount(for tab: MainTab) -> Int {
        switch tab {
        case .dashboard: return dashboardBadgeCount
        case .log:       return 0 // Log uses danger dot, not numeric badge
        case .downloads: return downloadsBadgeCount
        }
    }
}
