import SwiftUI

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    let action: (() -> Void)?
    let actionLabel: String

    init(
        symbol: String,
        title: String,
        message: String,
        action: (() -> Void)? = nil,
        actionLabel: String = "Start"
    ) {
        self.symbol = symbol
        self.title = title
        self.message = message
        self.action = action
        self.actionLabel = actionLabel
    }

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.s4) {
            Image(systemName: symbol)
                .font(.system(size: 32))
                .foregroundStyle(DesignTokens.typeSecondary)

            Text(title)
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(DesignTokens.typeSecondary)
                .multilineTextAlignment(.center)

            if let action {
                Button(action: action) {
                    Text(actionLabel)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .padding(.top, DesignTokens.Spacing.s2)
            }
        }
        .padding(DesignTokens.Spacing.s6)
    }
}