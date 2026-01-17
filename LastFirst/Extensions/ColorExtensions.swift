import SwiftUI

extension Color {
    // App theme colors
    static let appBackground = Color("AppBackground")
    static let appForeground = Color("AppForeground")
    static let accentRed = Color("AccentRed")

    // Computed colors based on color scheme
    static func adaptiveGray(_ opacity: Double) -> Color {
        return Color.gray.opacity(opacity)
    }
}

// Custom color scheme support
struct ThemeColors {
    let background: Color
    let foreground: Color
    let secondaryText: Color
    let accentColor: Color
    let dialBackground: Color
    let dialShadow: Color

    static let light = ThemeColors(
        background: Color(UIColor.systemBackground),
        foreground: Color.primary,
        secondaryText: Color.secondary,
        accentColor: Color.red,
        dialBackground: Color(white: 0.95),
        dialShadow: Color.black.opacity(0.1)
    )

    static let dark = ThemeColors(
        background: Color(UIColor.systemBackground),
        foreground: Color.primary,
        secondaryText: Color.secondary,
        accentColor: Color.red,
        dialBackground: Color(white: 0.15),
        dialShadow: Color.black.opacity(0.3)
    )
}

// Environment key for theme
struct ThemeKey: EnvironmentKey {
    static let defaultValue: ThemeColors = .light
}

extension EnvironmentValues {
    var theme: ThemeColors {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
