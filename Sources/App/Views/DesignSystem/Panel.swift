import SwiftUI

struct Panel<Content: View>: View {
    let cornerRadius: CGFloat
    @ViewBuilder let content: () -> Content

    init(cornerRadius: CGFloat = DesignTokens.Radii.panel,
         @ViewBuilder content: @escaping () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content
    }

    var body: some View {
        content()
            .padding(DesignTokens.Spacing.s5)
            .background(DesignTokens.panelGradient)
            .cornerRadius(cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(DesignTokens.separatorStrong, lineWidth: 1)
            )
            .shadow(
                color: DesignTokens.Elevation.mid.color,
                radius: DesignTokens.Elevation.mid.y,
                x: DesignTokens.Elevation.mid.x,
                y: DesignTokens.Elevation.mid.y
            )
    }
}