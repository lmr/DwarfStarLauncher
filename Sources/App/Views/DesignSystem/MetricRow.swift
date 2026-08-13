import SwiftUI

struct MetricRow: View {
    let label: String
    let value: String
    let valueTint: Color

    init(label: String, value: String, valueTint: Color = .primary) {
        self.label = label
        self.value = value
        self.valueTint = valueTint
    }

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.s2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(DesignTokens.typeSecondary)

            Spacer()

            Text(value)
                .font(.subheadline)
                .foregroundStyle(valueTint)
                .monospacedDigit()
        }
    }
}