import SwiftUI

enum DesignTokens {

    // MARK: - Surfaces

    static let cardSurface: Color = Color(nsColor: NSColor.textBackgroundColor).opacity(0.85)
    static let raisedSurface: Color = Color(nsColor: NSColor.windowBackgroundColor).opacity(0.95)
    static let panelGradient = LinearGradient(
        colors: [Color(nsColor: NSColor.windowBackgroundColor).opacity(0.97), Color(nsColor: NSColor.windowBackgroundColor).opacity(0.92)],
        startPoint: .top,
        endPoint: .bottom
    )

    // MARK: - Type Tiers

    static let typePrimary: Color = Color.primary
    static let typeSecondary: Color = Color.secondary
    static let typeTertiary: Color = Color.secondary.opacity(0.7)

    // MARK: - Separators

    static let separator: Color = Color.secondary.opacity(0.2)
    static let separatorStrong: Color = Color.secondary.opacity(0.4)

    // MARK: - Status Colors

    static let success: Color = Color.green
    static let warning: Color = Color.orange
    static let danger: Color = Color.red

    // MARK: - Spacing

    enum Spacing {
        static let s1: CGFloat = 4
        static let s2: CGFloat = 8
        static let s3: CGFloat = 12
        static let s4: CGFloat = 16
        static let s5: CGFloat = 20
        static let s6: CGFloat = 24
        static let s7: CGFloat = 32
    }

    // MARK: - Component Heights
    enum Height {

        /// Maximum vertical extent for the bottom tab bar navigation.
        static let bottomTabBarMax: CGFloat = 130

        /// Tab icon rendering size in points.
        static let tabIconSize: CGFloat = 60
    }

    // MARK: - Radii

    enum Radii {
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 14
        static let panel: CGFloat = 18
    }

    // MARK: - Elevation

    enum Elevation {
        static let low: (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) = (
            Color.black.opacity(0.06), DesignTokens.Radii.s, 0, 1
        )
        static let mid: (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) = (
            Color.black.opacity(0.08), DesignTokens.Radii.m, 0, 3
        )
        static let hi: (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) = (
            Color.black.opacity(0.10), DesignTokens.Radii.l, 0, 6
        )
    }
}
