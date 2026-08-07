import SwiftUI

/// Storm-chaser dark palette. Accent brightness scales with lightning activity,
/// hue drifts with the time of day — see `ThemeEngine`.
struct StormTheme: Equatable {
    var background: Color
    var surface: Color
    var surfaceRaised: Color
    var primaryText: Color
    var secondaryText: Color
    /// The electric accent — buttons, live values, the bolt itself.
    var accent: Color
    var accentGlow: Color
    var danger: Color
    var safe: Color
    /// 0…1, how "charged" the UI looks. Drives glow radius and pulse strength.
    var charge: Double

    static let night = StormTheme(
        background: Color(red: 0.03, green: 0.03, blue: 0.06),
        surface: Color(red: 0.07, green: 0.07, blue: 0.11),
        surfaceRaised: Color(red: 0.11, green: 0.11, blue: 0.17),
        primaryText: Color(white: 0.96),
        secondaryText: Color(white: 0.62),
        accent: Color(red: 0.53, green: 0.42, blue: 1.0),
        accentGlow: Color(red: 0.67, green: 0.55, blue: 1.0),
        danger: Color(red: 1.0, green: 0.34, blue: 0.33),
        safe: Color(red: 0.29, green: 0.85, blue: 0.62),
        charge: 0
    )

    static let dusk = StormTheme(
        background: Color(red: 0.05, green: 0.04, blue: 0.09),
        surface: Color(red: 0.10, green: 0.08, blue: 0.15),
        surfaceRaised: Color(red: 0.15, green: 0.12, blue: 0.22),
        primaryText: Color(white: 0.97),
        secondaryText: Color(white: 0.66),
        accent: Color(red: 0.85, green: 0.45, blue: 0.95),
        accentGlow: Color(red: 0.95, green: 0.60, blue: 1.0),
        danger: Color(red: 1.0, green: 0.40, blue: 0.30),
        safe: Color(red: 0.32, green: 0.86, blue: 0.63),
        charge: 0
    )

    static let day = StormTheme(
        background: Color(red: 0.07, green: 0.08, blue: 0.11),
        surface: Color(red: 0.12, green: 0.13, blue: 0.17),
        surfaceRaised: Color(red: 0.17, green: 0.19, blue: 0.24),
        primaryText: Color(white: 0.98),
        secondaryText: Color(white: 0.70),
        accent: Color(red: 0.33, green: 0.72, blue: 1.0),
        accentGlow: Color(red: 0.55, green: 0.85, blue: 1.0),
        danger: Color(red: 1.0, green: 0.38, blue: 0.32),
        safe: Color(red: 0.25, green: 0.83, blue: 0.60),
        charge: 0
    )

    /// Blend two palettes so time-of-day transitions do not snap.
    static func blend(_ lhs: StormTheme, _ rhs: StormTheme, amount: Double) -> StormTheme {
        let t = min(max(amount, 0), 1)
        func mix(_ a: Color, _ b: Color) -> Color {
            let ca = a.resolvedComponents
            let cb = b.resolvedComponents
            return Color(
                red: ca.r + (cb.r - ca.r) * t,
                green: ca.g + (cb.g - ca.g) * t,
                blue: ca.b + (cb.b - ca.b) * t
            )
        }
        return StormTheme(
            background: mix(lhs.background, rhs.background),
            surface: mix(lhs.surface, rhs.surface),
            surfaceRaised: mix(lhs.surfaceRaised, rhs.surfaceRaised),
            primaryText: mix(lhs.primaryText, rhs.primaryText),
            secondaryText: mix(lhs.secondaryText, rhs.secondaryText),
            accent: mix(lhs.accent, rhs.accent),
            accentGlow: mix(lhs.accentGlow, rhs.accentGlow),
            danger: mix(lhs.danger, rhs.danger),
            safe: mix(lhs.safe, rhs.safe),
            charge: lhs.charge + (rhs.charge - lhs.charge) * t
        )
    }

    /// Glow radius for accented elements at the current charge.
    var glowRadius: CGFloat { 4 + 14 * charge }
}

extension Color {
    /// sRGB components. Needed for palette blending; SwiftUI has no public mixer on iOS 17.
    var resolvedComponents: (r: Double, g: Double, b: Double) {
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b))
        #else
        return (0, 0, 0)
        #endif
    }
}

private struct StormThemeKey: EnvironmentKey {
    static let defaultValue = StormTheme.night
}

extension EnvironmentValues {
    var stormTheme: StormTheme {
        get { self[StormThemeKey.self] }
        set { self[StormThemeKey.self] = newValue }
    }
}
