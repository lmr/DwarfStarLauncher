import SwiftUI

struct Card<Content: View>: View {
    @ViewBuilder let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .padding(DesignTokens.Spacing.s4)
            .background(DesignTokens.cardSurface)
            .cornerRadius(DesignTokens.Radii.m)
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radii.m)
                    .stroke(DesignTokens.separator, lineWidth: 1)
            )
    }
}