import SwiftUI

/// In-app banner for one `StormAlert`, colored by severity.
struct AlertBanner: View {
    let alert: StormAlert
    var onDismiss: () -> Void

    @Environment(\.stormTheme) private var theme

    private var tint: Color {
        switch alert.kind {
        case .immediate, .danger: theme.danger
        case .approaching: theme.accent
        case .clearing: theme.safe
        }
    }

    private var symbolName: String {
        switch alert.kind {
        case .immediate: "exclamationmark.octagon.fill"
        case .danger: "exclamationmark.triangle.fill"
        case .approaching: "cloud.bolt.rain.fill"
        case .clearing: "checkmark.circle.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbolName)
                .font(.title3)
                .foregroundStyle(tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(alert.title)
                    .font(.headline)
                    .foregroundStyle(theme.primaryText)
                Text(alert.message)
                    .font(.subheadline)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.secondaryText)
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(String(localized: "alert.banner.dismiss",
                                       defaultValue: "Warnung schließen"))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.surfaceRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(tint.opacity(0.6), lineWidth: 1)
                )
        )
    }
}
