import SwiftUI

struct TopChromeStrip: View {
    @Environment(ServerManager.self) private var serverManager

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.s4) {
            statusIndicator
            transportControls
        }
        .padding(.horizontal, DesignTokens.Spacing.s5)
    }

    // MARK: - Status Indicator (single dot + label; green only when running)

    @ViewBuilder
    private var statusIndicator: some View {
        HStack(spacing: DesignTokens.Spacing.s1) {
            Circle()
                .fill(colorForStatus(serverManager.status))
                .frame(width: 8, height: 8)

            Text(serverManager.status.label)
                .font(.caption)
                .foregroundStyle(DesignTokens.typeSecondary)
        }
    }

    private func colorForStatus(_ status: ServerStatus) -> Color {
        switch status {
        case .starting: return DesignTokens.warning
        case .running:  return DesignTokens.success
        case .stopped:  return DesignTokens.typeTertiary
        case .error:    return DesignTokens.danger
        }
    }

    // MARK: - Transport Controls (play / stop / restart)

    @ViewBuilder
    private var transportControls: some View {
        // ControlGroup with a custom style renders the play/stop/restart
        // actions as a single bordered pill group. (The stock .palette style
        // resolves to a dropdown menu in this inline context on macOS.)
        ControlGroup {
            Button {
                serverManager.spawn(config: serverManager.config)
            } label: {
                Image(systemName: "play.fill")
            }
            .disabled(serverManager.status == .running || serverManager.status == .starting)

            Button {
                serverManager.stop()
            } label: {
                Image(systemName: "stop.fill")
            }
            .disabled(serverManager.status != .running && serverManager.status != .starting)

            Button {
                serverManager.restart()
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .disabled(serverManager.status != .running && serverManager.status != .starting)
        }
    }
}
