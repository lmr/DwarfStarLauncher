import Foundation

enum TokenCountFormatter {
    static func humanize(_ count: Int64) -> String {
        guard count >= 1_000 else { return String(count) }

        let units: [(scale: Double, suffix: String)] = [
            (1_000_000_000, "B"),
            (1_000_000, "M"),
            (1_000, "K")
        ]
        let rawValue = Double(count)
        var unitIndex = units.firstIndex { rawValue >= $0.scale } ?? units.count - 1
        var scaledValue = rawValue / units[unitIndex].scale

        // Promote values that would round to 1000 of the current unit, e.g.
        // 999,950 → 1M instead of displaying the awkward "1000K".
        let roundedTenths = Int64((scaledValue * 10).rounded())
        if roundedTenths >= 10_000, unitIndex > 0 {
            unitIndex -= 1
            scaledValue = rawValue / units[unitIndex].scale
        }

        let tenths = Int64((scaledValue * 10).rounded())
        let whole = tenths / 10
        let fraction = tenths % 10
        let value = fraction == 0 ? String(whole) : "\(whole).\(fraction)"
        return value + units[unitIndex].suffix
    }
}
