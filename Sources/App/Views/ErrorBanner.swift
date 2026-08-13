import SwiftUI

struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.s2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DesignTokens.danger)
                .font(.caption)

            Text(message)
                .font(.caption)
                .foregroundStyle(DesignTokens.typePrimary)
                .lineLimit(2)

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(DesignTokens.typeTertiary)
        }
        .padding(.horizontal, DesignTokens.Spacing.s3)
        .padding(.vertical, DesignTokens.Spacing.s2)
        .background(DesignTokens.cardSurface, in: RoundedRectangle(cornerRadius: DesignTokens.Radii.m))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radii.m)
                .stroke(DesignTokens.danger.opacity(0.3), lineWidth: 1)
        )
    }
}
