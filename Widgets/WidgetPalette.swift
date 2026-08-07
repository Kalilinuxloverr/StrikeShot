import SwiftUI

/// Widget-local palette. The widget target cannot see StormTheme, so the
/// night palette is mirrored here in miniature.
enum WidgetPalette {
    static let background = Color(red: 0.03, green: 0.03, blue: 0.06)
    static let surface = Color(red: 0.11, green: 0.11, blue: 0.17)
    static let primaryText = Color(white: 0.96)
    static let secondaryText = Color(white: 0.62)
    static let accent = Color(red: 0.53, green: 0.42, blue: 1.0)
    static let danger = Color(red: 1.0, green: 0.34, blue: 0.33)
    static let safe = Color(red: 0.29, green: 0.85, blue: 0.62)
}
