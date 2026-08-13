import SwiftUI
import Charts

// MARK: - Chart Data Point (used by dashboard decode chart)

struct ChartPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let value: Double
}

struct DashboardView: View {
    @Environment(ServerManager.self) private var serverManager
    @Environment(StatusMonitor.self) private var statusMonitor

    private var isRunning: Bool { serverManager.status == .running }
    private var isStarting: Bool { serverManager.status == .starting }
    private var isStopped: Bool { serverManager.status == .stopped }

    // MARK: - Warm-up gating

    private var hasRealGeneration: Bool {
        statusMonitor.history.contains { $0.generationTokensPerSecond > 0 || $0.prefillTokensPerSecond > 0 }
    }

    private var warmUpComplete: Bool {
        isRunning && hasRealGeneration
    }

    // MARK: - StatTile values

    private var prefillTile: StatTile {
        let value = warmUpComplete ? String(format: "%.1f", statusMonitor.prefillTokensPerSecond) : "—"
        return StatTile(
            label: "Prefill",
            value: value,
            unit: "tok/s",
            systemImage: "speedometer"
        )
    }

    private var generationTile: StatTile {
        let value = warmUpComplete ? String(format: "%.1f", statusMonitor.generationTokensPerSecond) : "—"
        return StatTile(
            label: "Generation",
            value: value,
            unit: "tok/s",
            systemImage: "speedometer"
        )
    }

    private var contextTile: StatTile {
        guard warmUpComplete, let used = statusMonitor.contextUsed, let total = statusMonitor.contextTotal else {
            return StatTile(label: "Context", value: "—", unit: "")
        }
        let value = String(used)
        return StatTile(
            label: "Context",
            value: value,
            unit: "/ \(total)",
            systemImage: "memorychip"
        )
    }

    private var memoryTile: StatTile {
        guard warmUpComplete, let usedMB = statusMonitor.systemMemoryUsedMB, let totalMB = statusMonitor.systemMemoryTotalMB else {
            return StatTile(label: "Memory", value: "—", unit: "")
        }
        let value = String(format: "%.0f", usedMB)
        return StatTile(
            label: "Memory",
            value: value,
            unit: "/ \(String(format: "%.0f", totalMB)) MB",
            systemImage: "cpu"
        )
    }

    private var gpuTile: StatTile {
        guard warmUpComplete, let gpu = statusMonitor.gpuLoadPercent else {
            return StatTile(label: "GPU", value: "—", unit: "")
        }
        let value = String(format: "%.0f", gpu)
        return StatTile(
            label: "GPU",
            value: value,
            unit: "%",
            systemImage: "cpu"
        )
    }

    // MARK: - Metric chart data

    private var recentPrefillData: [ChartPoint] {
        let cutoff = Date().addingTimeInterval(-60)
        return statusMonitor.history
            .filter { $0.timestamp >= cutoff }
            .map { snap in
                ChartPoint(timestamp: snap.timestamp, value: snap.prefillTokensPerSecond)
            }
    }

    private var recentGenData: [ChartPoint] {
        let cutoff = Date().addingTimeInterval(-60)
        return statusMonitor.history
            .filter { $0.timestamp >= cutoff }
            .map { snap in
                ChartPoint(timestamp: snap.timestamp, value: snap.generationTokensPerSecond)
            }
    }

    private var recentContextData: [ChartPoint] {
        let cutoff = Date().addingTimeInterval(-60)
        return statusMonitor.history
            .filter { $0.timestamp >= cutoff }
            .compactMap { snap in
                guard let used = snap.contextUsed, let total = snap.contextTotal, total > 0 else { return nil }
                return ChartPoint(timestamp: snap.timestamp, value: Double(used) / Double(total) * 100)
            }
    }

    private var recentMemoryData: [ChartPoint] {
        let cutoff = Date().addingTimeInterval(-60)
        return statusMonitor.history
            .filter { $0.timestamp >= cutoff }
            .compactMap { snap in
                guard let used = snap.systemMemoryUsedMB, let total = snap.systemMemoryTotalMB, total > 0 else { return nil }
                return ChartPoint(timestamp: snap.timestamp, value: used / total * 100)
            }
    }

    private var recentGPUData: [ChartPoint] {
        let cutoff = Date().addingTimeInterval(-60)
        return statusMonitor.history
            .filter { $0.timestamp >= cutoff }
            .compactMap { snap in
                snap.gpuLoadPercent.map { ChartPoint(timestamp: snap.timestamp, value: $0) }
            }
    }

    private func metricChart(title: String, data: [ChartPoint]) -> some View {
        Card {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.s3) {
                Text(title)
                    .font(.headline)

                Chart(data) { point in
                    AreaMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(Color.accentColor)
                    .interpolationMethod(.monotone)
                }
                .frame(height: 160)
                .chartXAxis {
                    AxisMarks(values: .automatic)
                }
                .chartYAxis {
                    AxisMarks(values: .automatic)
                }
            }
            .padding(DesignTokens.Spacing.s3)
        }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.s5) {
                if isStopped {
                    EmptyStateView(
                        symbol: "play.circle",
                        title: "Server Stopped",
                        message: "Start the server to see live metrics."
                    ) {
                        serverManager.spawn(config: serverManager.config)
                    }
                    .padding(.top, DesignTokens.Spacing.s6)
                } else if isStarting {
                    VStack(spacing: DesignTokens.Spacing.s4) {
                        ProgressView()
                        Text("Starting server…")
                            .font(.subheadline)
                            .foregroundStyle(DesignTokens.typeSecondary)
                    }
                    .padding(.top, DesignTokens.Spacing.s6)
                } else {
                    // StatTile row — horizontal layout, equal-width tiles
                    HStack(spacing: DesignTokens.Spacing.s4) {
                        prefillTile
                        generationTile
                        contextTile
                        memoryTile
                        gpuTile
                    }
                    .padding(.top, DesignTokens.Spacing.s2)
                    .padding(.horizontal, DesignTokens.Spacing.s4)

                    // Metric charts — always visible (permanent)
                    VStack(spacing: DesignTokens.Spacing.s4) {
                        metricChart(title: "Prefill Speed", data: recentPrefillData)
                        metricChart(title: "Generation Speed", data: recentGenData)
                        metricChart(title: "System Memory", data: recentMemoryData)
                        metricChart(title: "GPU Load", data: recentGPUData)
                    }
                    .padding(.horizontal, DesignTokens.Spacing.s4)

                    // Warm-up indicator
                    if isRunning && !warmUpComplete {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.caption)
                                .foregroundStyle(DesignTokens.warning)
                            Text("Warming up — awaiting first prefill or decode…")
                                .font(.caption)
                                .foregroundStyle(DesignTokens.typeSecondary)
                        }
                        .padding(.horizontal, DesignTokens.Spacing.s4)
                    }
                }
            }
        }
        .background(Color.clear)
    }
}
