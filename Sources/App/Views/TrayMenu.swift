import SwiftUI
import AppKit

struct TrayMenu: View {
    @Environment(ServerManager.self) private var serverManager
    @Environment(StatusMonitor.self) private var statusMonitor
    @Environment(ModelManager.self) private var modelManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            statusSection
            Divider()
            modelInfoSection
            Divider()
            throughputSection
            Divider()
            controlsSection
            Divider()
            quickActionsSection
            Divider()
            showSection
            Divider()
            quitSection
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(colorForStatus(serverManager.status))
                .frame(width: 10, height: 10)
            Text(serverManager.status.label)
                .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Model Info

    private var modelInfoSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let model = modelManager.selectedModel {
                Text(model.name)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("No model selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if serverManager.config.enableMtp, let mtp = modelManager.selectedMtpModel {
                Text("MTP: \(mtp.name)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    // MARK: - Throughput

    @ViewBuilder
    private var throughputSection: some View {
        if serverManager.status == .running || serverManager.status == .starting {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("prefill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1f t/s", statusMonitor.prefillTokensPerSecond))
                        .font(.caption)
                        .monospacedDigit()
                }
                HStack(spacing: 4) {
                    Text("gen")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1f t/s", statusMonitor.generationTokensPerSecond))
                        .font(.caption)
                        .monospacedDigit()
                }
                if let used = statusMonitor.contextUsed, let total = statusMonitor.contextTotal {
                    let pct = statusMonitor.contextPercent ?? 0
                    HStack(spacing: 4) {
                        Text("ctx")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(used)/\(total) (\(String(format: "%.0f", pct))%)")
                            .font(.caption)
                            .monospacedDigit()
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Controls

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button("Start Server") {
                serverManager.spawn(config: serverManager.config)
            }
            .disabled(serverManager.status == .running || serverManager.status == .starting)

            Button("Stop Server") {
                serverManager.stop()
            }
            .disabled(serverManager.status != .running && serverManager.status != .starting)

            Button("Restart Server") {
                serverManager.restart()
            }
            .disabled(serverManager.status != .running && serverManager.status != .starting)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    // MARK: - Quick Actions

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button("Open Models Folder") {
                NSWorkspace.shared.open(PathResolver.modelsDir)
            }
            Button("Open Config File") {
                NSWorkspace.shared.open(PathResolver.configFile)
            }
            Button("Open Logs") {
                NSWorkspace.shared.open(PathResolver.dataRoot)
            }
            SettingsLink {
                Text("Settings")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    // MARK: - Show

    private var showSection: some View {
        Button("Show DwarfStarLauncher") {
            openWindow(id: "main")
            dismiss()
        }
        .keyboardShortcut("s", modifiers: .command)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Quit

    private var quitSection: some View {
        Button("Quit DwarfStarLauncher") {
            NSApp.terminate(nil)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private func colorForStatus(_ status: ServerStatus) -> Color {
        switch status {
        case .starting: return .yellow
        case .running:  return .green
        case .stopped:  return .gray
        case .error:    return .red
        }
    }
}
