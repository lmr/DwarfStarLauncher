import SwiftUI

struct StatTile: View {
    let label: String
    let value: String
    let unit: String?
    let systemImage: String?
    let caption: String?

    init(
        label: String,
        value: String,
        unit: String? = nil,
        systemImage: String? = nil,
        caption: String? = nil
    ) {
        self.label = label
        self.value = value
        self.unit = unit
        self.systemImage = systemImage
        self.caption = caption
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s1) {
            HStack(spacing: DesignTokens.Spacing.s1) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption)
                        .foregroundStyle(DesignTokens.typeTertiary)
                }

                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.typeSecondary)

                Spacer()
            }

            Text(value)
                .font(.largeTitle)
                .fontWeight(.semibold)
                .monospacedDigit()

            if let unit {
                Text(unit)
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.typeTertiary)
                    .monospacedDigit()
            }

            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.typeTertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}