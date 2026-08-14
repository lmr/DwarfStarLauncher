import SwiftUI
import HuggingFaceDownloader

struct DownloadsView: View {
    @Environment(ModelDownloader.self) private var modelDownloader

    /// Which category sections are expanded. Defaults to the first category
    /// (DeepSeek Flash) expanded and the rest collapsed.
    @State private var expanded: Set<DownloadCategory> = [.deepSeekFlash]

    private var hasActiveDownloads: Bool {
        modelDownloader.currentTarget != nil && modelDownloader.downloadState != .idle
    }

    private var hasCompletedDownloads: Bool {
        modelDownloader.availableTargets.contains { target in
            modelDownloader.isDownloaded(target)
        }
    }

    private var categories: [DownloadCategory] { DownloadCategory.allCases }

    var body: some View {
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.s5) {
                if modelDownloader.availableTargets.isEmpty {
                    EmptyStateView(
                        symbol: "arrow.down.circle",
                        title: "No Models Available",
                        message: "No download targets configured."
                    )
                    .padding(.top, DesignTokens.Spacing.s6)
                } else {
                    ForEach(categories) { category in
                        DisclosureGroup(isExpanded: sectionBinding(for: category)) {
                            ForEach(modelDownloader.availableTargets.filter { $0.category == category }) { target in
                                modelCard(for: target)
                            }
                        } label: {
                            sectionHeader(for: category)
                        }
                        .disclosureGroupStyle(ChevronDisclosureGroupStyle())
                        .padding(.horizontal, DesignTokens.Spacing.s4)
                    }
                }
            }
        }
    }

    // MARK: - Model Card

    private func modelCard(for target: DownloadTarget) -> some View {
        Card {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.s3) {
                // Header: target name + status
                HStack {
                    Text(target.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Spacer()

                    statusBadge(for: target)
                }

                // Progress row
                progressRow(for: target)

                // File status
                fileStatusRow(for: target)

                // Actions
                actionRow(for: target)
            }
            .padding(DesignTokens.Spacing.s4)
        }
    }

    // MARK: - Status Badge

    @ViewBuilder
    private func statusBadge(for target: DownloadTarget) -> some View {
        switch modelDownloader.downloadState(for: target) {
        case .idle:
            Text("Available")
                .font(.caption)
                .foregroundStyle(DesignTokens.typeSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(DesignTokens.separator)
                .cornerRadius(4)

        case .progress:
            // Active download is conveyed by the linear bar fill + Cancel button.
            EmptyView()

        case .complete:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(DesignTokens.success)
                .font(.caption)

        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DesignTokens.danger)
                .font(.caption)

        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(DesignTokens.danger)
                .font(.caption)
        }
    }

    // MARK: - Progress Row

    private func progressRow(for target: DownloadTarget) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s2) {
            // Always-present linear bar: 0 idle, percent/100 in progress, 1.0 complete,
            // danger tint on error. Stable height across all download states.
            ProgressView(value: progressValue(for: target))
                .progressViewStyle(.linear)
                .tint(progressTint(for: target))

            if case .progress(_, let bytesDownloaded, let totalBytes, let speed, let eta) = modelDownloader.downloadState(for: target) {
                HStack(spacing: DesignTokens.Spacing.s3) {
                    statSlot(
                        label: "Size",
                        value: formatSize(bytes: bytesDownloaded, total: totalBytes),
                        minWidth: 190
                    )
                    statSlot(
                        label: "Speed",
                        value: formatSpeed(speed),
                        minWidth: 100
                    )
                    statSlot(
                        label: "ETA",
                        value: eta > 0 ? formatETA(eta) : "—",
                        minWidth: 90
                    )
                }
            }
        }
    }

    private func progressValue(for target: DownloadTarget) -> Double {
        switch modelDownloader.downloadState(for: target) {
        case .idle:
            return 0
        case .progress(let percent, _, _, _, _):
            return percent / 100.0
        case .complete:
            return 1.0
        case .error, .failed:
            return 0
        }
    }

    private func progressTint(for target: DownloadTarget) -> Color {
        switch modelDownloader.downloadState(for: target) {
        case .error, .failed:
            return DesignTokens.danger
        default:
            return Color.accentColor
        }
    }

    /// Right-aligned fixed-width monospaced stat slot. The column keeps a constant
    /// width (minWidth + maxWidth distribution) so value changes reflow only inside
    /// their own slot and never shift neighbors — eliminating the progress jitter.
    private func statSlot(label: String, value: String, minWidth: CGFloat) -> some View {
        VStack(alignment: .trailing, spacing: DesignTokens.Spacing.s1) {
            Text(label)
                .font(.caption)
                .foregroundStyle(DesignTokens.typeSecondary)
            Text(value)
                .font(.subheadline)
                .monospaced()
                .foregroundStyle(DesignTokens.typePrimary)
        }
        .frame(minWidth: minWidth, maxWidth: .infinity, alignment: .trailing)
    }

    private func formatSize(bytes: Int64, total: Int64) -> String {
        let downloaded = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        let totalStr = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
        return "\(downloaded) / \(totalStr)"
    }

    private func formatSpeed(_ speed: Int64) -> String {
        let speedStr = ByteCountFormatter.string(fromByteCount: speed, countStyle: .file)
        return "\(speedStr)/s"
    }

    private func formatETA(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60

        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, secs)
        } else {
            return "\(secs)s"
        }
    }

    // MARK: - File Status Row

    private func fileStatusRow(for target: DownloadTarget) -> some View {
        let downloadedCount = modelDownloader.downloadedFileCount(for: target)
        let totalCount = target.files.count

        if downloadedCount < totalCount {
            return AnyView(
                MetricRow(
                    label: "Files",
                    value: "\(downloadedCount)/\(totalCount)",
                    valueTint: DesignTokens.warning
                )
            )
        } else {
            return AnyView(
                MetricRow(
                    label: "Files",
                    value: "All downloaded",
                    valueTint: DesignTokens.success
                )
            )
        }
    }

    // MARK: - Action Row

    private func actionRow(for target: DownloadTarget) -> some View {
        let state = modelDownloader.downloadState(for: target)

        return AnyView(
            HStack {
                switch state {
                case .idle, .error, .failed:
                    Button(hasPartialFiles(target) ? "Resume" : "Download") {
                        // Auto-expand the category so progress is never hidden.
                        expanded.insert(target.category)
                        modelDownloader.download(target: target)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                case .progress:
                    Button("Cancel") {
                        modelDownloader.cancel()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.secondary)
                    .controlSize(.small)

                case .complete:
                    Text("Complete")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.success)
                }
            }
        )
    }

    private func hasPartialFiles(_ target: DownloadTarget) -> Bool {
        target.files.contains { file in
            let partURL = PathResolver.partFileURL(for: file.localName)
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: partURL.path) else { return false }
            return (attrs[.size] as? Int64 ?? 0) > 0
        }
    }

    // MARK: - Collapsible Sections

    private func sectionBinding(for category: DownloadCategory) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(category) },
            set: { isExpanded in
                if isExpanded {
                    expanded.insert(category)
                } else {
                    expanded.remove(category)
                }
            }
        )
    }

    private func sectionHeader(for category: DownloadCategory) -> some View {
        HStack {
            Text(category.displayName)
                .font(.headline)
            Spacer()
            Image(systemName: expanded.contains(category) ? "chevron.down" : "chevron.right")
                .font(.caption)
                .foregroundStyle(DesignTokens.typeSecondary)
        }
        .padding(.horizontal, DesignTokens.Spacing.s4)
        .padding(.vertical, DesignTokens.Spacing.s1)
    }
}

// MARK: - Custom Disclosure Group Style

/// Replaces the default disclosure triangle with a custom chevron header that
/// matches the card styling, and collapses the content when not expanded.
private struct ChevronDisclosureGroupStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s4) {
            Button {
                withAnimation {
                    configuration.isExpanded.toggle()
                }
            } label: {
                configuration.label
            }
            .buttonStyle(.plain)

            if configuration.isExpanded {
                configuration.content
            }
        }
    }
}

// MARK: - Helpers

extension ModelDownloader {
    func downloadState(for target: DownloadTarget) -> DownloadState {
        if currentTarget == target {
            return downloadState
        }
        // Check the in-memory downloaded-state (background-refreshed) rather than
        // the catalog's `downloaded` flag, which is never mutated.
        if isDownloaded(target) {
            return .complete
        }
        return .idle
    }
}