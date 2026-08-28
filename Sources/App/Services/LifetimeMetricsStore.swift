import Foundation

/// File-backed storage for metrics that should survive app and server sessions.
final class LifetimeMetricsStore {
    private let fileURL: URL

    init(fileURL: URL = PathResolver.lifetimeMetricsFile) {
        self.fileURL = fileURL
    }

    func load() -> LifetimeMetrics {
        guard let data = try? Data(contentsOf: fileURL),
              let metrics = try? JSONDecoder().decode(LifetimeMetrics.self, from: data) else {
            return LifetimeMetrics()
        }
        return metrics
    }

    func save(_ metrics: LifetimeMetrics) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(metrics)
        try data.write(to: fileURL, options: .atomic)
    }
}
