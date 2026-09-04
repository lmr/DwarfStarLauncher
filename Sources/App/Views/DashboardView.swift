import SwiftUI
import Charts

// MARK: - Chart Data Point (used by dashboard decode chart)

struct ChartPoint: Identifiable {
    let id: String
    let timestamp: Date
    let value: Double

    init(timestamp: Date, value: Double, series: String) {
        self.id = "\(series)-\(timestamp.timeIntervalSinceReferenceDate)"
        self.timestamp = timestamp
        self.value = value
    }
}

private struct DashboardChartData {
    let prefill: [ChartPoint]
    let generation: [ChartPoint]
    let context: [ChartPoint]
    let memory: [ChartPoint]
    let gpu: [ChartPoint]
}

struct DashboardView: View {
    @Environment(ServerManager.self) private var serverManager
    @Environment(StatusMonitor.self) private var statusMonitor

    private var isRunning: Bool { serverManager.status == .running }
    private var isStarting: Bool { serverManager.status == .starting }
    private var isStopped: Bool { serverManager.status == .stopped }

    // MARK: - Warm-up gating

    private var hasRealGeneration: Bool {
        statusMonitor.hasRealThroughput
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

    private var chartData: DashboardChartData {
        let cutoff = Date().addingTimeInterval(-60)
        // `history` is time ordered, so take only the bounded tail and stop
        // discarding once the one-minute window begins. Each of the five
        // series is built in this single pass per view update.
        let snapshots = statusMonitor.history.suffix(1000).drop(while: { $0.timestamp < cutoff })
        var prefill: [ChartPoint] = []
        var generation: [ChartPoint] = []
        var context: [ChartPoint] = []
        var memory: [ChartPoint] = []
        var gpu: [ChartPoint] = []

        for snap in snapshots {
            prefill.append(ChartPoint(timestamp: snap.timestamp, value: snap.prefillTokensPerSecond, series: "prefill"))
            generation.append(ChartPoint(timestamp: snap.timestamp, value: snap.generationTokensPerSecond, series: "generation"))
            if let used = snap.contextUsed, let total = snap.contextTotal, total > 0 {
                context.append(ChartPoint(timestamp: snap.timestamp, value: Double(used) / Double(total) * 100, series: "context"))
            }
            if let used = snap.systemMemoryUsedMB, let total = snap.systemMemoryTotalMB, total > 0 {
                memory.append(ChartPoint(timestamp: snap.timestamp, value: used / total * 100, series: "memory"))
            }
            if let value = snap.gpuLoadPercent {
                gpu.append(ChartPoint(timestamp: snap.timestamp, value: value, series: "gpu"))
            }
        }
        return DashboardChartData(prefill: prefill, generation: generation, context: context, memory: memory, gpu: gpu)
    }

    // MARK: - Lifetime metrics

    private var lifetimeMetricsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.s3) {
                HStack {
                    Text("Lifetime Metrics")
                        .font(.headline)
                    Spacer()
                    Text("Across server sessions")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.typeTertiary)
                }

                HStack(spacing: DesignTokens.Spacing.s4) {
                    StatTile(
                        label: "Avg. Prefill",
                        value: formatSpeed(statusMonitor.lifetimeMetrics.averagePrefillTokensPerSecond),
                        unit: "tok/s",
                        systemImage: "speedometer"
                    )
                    StatTile(
                        label: "Avg. Generation",
                        value: formatSpeed(statusMonitor.lifetimeMetrics.averageGenerationTokensPerSecond),
                        unit: "tok/s",
                        systemImage: "speedometer"
                    )
                    StatTile(
                        label: "Prefilled",
                        value: TokenCountFormatter.humanize(statusMonitor.lifetimeMetrics.prefilledTokenCount),
                        unit: "tokens",
                        systemImage: "arrow.down"
                    )
                    StatTile(
                        label: "Generated",
                        value: TokenCountFormatter.humanize(statusMonitor.lifetimeMetrics.generatedTokenCount),
                        unit: "tokens",
                        systemImage: "arrow.up"
                    )
                }
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.s4)
    }

    private func formatSpeed(_ speed: Double?) -> String {
        guard let speed else { return "—" }
        return String(format: "%.1f", speed)
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
        let data = chartData
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.s5) {
                lifetimeMetricsCard

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
                    Card {
                        HStack(spacing: DesignTokens.Spacing.s4) {
                            prefillTile
                            generationTile
                            contextTile
                            memoryTile
                            gpuTile
                        }
                    }
                    .padding(.top, DesignTokens.Spacing.s2)
                    .padding(.horizontal, DesignTokens.Spacing.s4)

                    // Metric charts — always visible (permanent)
                    VStack(spacing: DesignTokens.Spacing.s4) {
                        metricChart(title: "Prefill Speed", data: data.prefill)
                        metricChart(title: "Generation Speed", data: data.generation)
                        metricChart(title: "Context Usage", data: data.context)
                        metricChart(title: "System Memory", data: data.memory)
                        metricChart(title: "GPU Load", data: data.gpu)
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
