import Foundation

/// Persistent inference totals accumulated from completed ds4-server requests.
///
/// The average speeds are derived from the accumulated token counts and elapsed
/// processing time, which makes them weighted by the amount of work completed.
struct LifetimeMetrics: Codable, Equatable {
    var prefilledTokenCount: Int64 = 0
    var generatedTokenCount: Int64 = 0
    var prefillDurationSeconds: Double = 0
    var generationDurationSeconds: Double = 0

    var averagePrefillTokensPerSecond: Double? {
        average(tokens: prefilledTokenCount, duration: prefillDurationSeconds)
    }

    var averageGenerationTokensPerSecond: Double? {
        average(tokens: generatedTokenCount, duration: generationDurationSeconds)
    }

    mutating func addPrefill(tokens: Int64, duration: Double?) {
        guard tokens > 0 else { return }
        prefilledTokenCount += tokens
        if let duration, duration > 0 {
            prefillDurationSeconds += duration
        }
    }

    mutating func addGeneration(tokens: Int64, duration: Double?) {
        guard tokens > 0 else { return }
        generatedTokenCount += tokens
        if let duration, duration > 0 {
            generationDurationSeconds += duration
        }
    }

    private func average(tokens: Int64, duration: Double) -> Double? {
        guard tokens > 0, duration > 0 else { return nil }
        return Double(tokens) / duration
    }

    private enum CodingKeys: String, CodingKey {
        case prefilledTokenCount
        case generatedTokenCount
        case prefillDurationSeconds
        case generationDurationSeconds
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        prefilledTokenCount = try container.decodeIfPresent(Int64.self, forKey: .prefilledTokenCount) ?? 0
        generatedTokenCount = try container.decodeIfPresent(Int64.self, forKey: .generatedTokenCount) ?? 0
        prefillDurationSeconds = try container.decodeIfPresent(Double.self, forKey: .prefillDurationSeconds) ?? 0
        generationDurationSeconds = try container.decodeIfPresent(Double.self, forKey: .generationDurationSeconds) ?? 0
    }
}
