import ActivityKit
import SwiftUI
import WidgetKit

struct StormLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StormActivityAttributes.self) { context in
            StormActivityLockView(
                snapshot: context.state.snapshot,
                placeName: context.attributes.placeName
            )
            .activityBackgroundTint(WidgetPalette.background)
            .activitySystemActionForegroundColor(WidgetPalette.accent)
        } dynamicIsland: { context in
            let snapshot = context.state.snapshot
            let tint = snapshot.isImmediateDanger ? WidgetPalette.danger : WidgetPalette.accent
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text("\(snapshot.strikeCount)")
                            .font(.title3.bold())
                            .foregroundStyle(WidgetPalette.primaryText)
                    } icon: {
                        Image(systemName: "bolt.fill")
                            .foregroundStyle(tint)
                    }
                    .accessibilityLabel(String(localized: "live.strikes.a11y",
                                               defaultValue: "\(snapshot.strikeCount) Blitze im Umkreis"))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    HStack(spacing: 4) {
                        Text(StormText.distance(snapshot))
                            .font(.title3.bold())
                            .foregroundStyle(tint)
                        Image(systemName: snapshot.trend.symbolName)
                            .font(.footnote)
                            .foregroundStyle(WidgetPalette.secondaryText)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        if snapshot.isImmediateDanger {
                            Text(StormText.shelter)
                                .font(.footnote.bold())
                                .foregroundStyle(WidgetPalette.danger)
                        } else if let eta = StormText.eta(snapshot) {
                            Text(eta)
                                .font(.footnote)
                                .foregroundStyle(WidgetPalette.primaryText)
                        }
                        Text(context.attributes.placeName)
                            .font(.caption2)
                            .foregroundStyle(WidgetPalette.secondaryText)
                    }
                }
            } compactLeading: {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(tint)
            } compactTrailing: {
                Text(StormText.distance(snapshot))
                    .font(.caption2.bold())
                    .foregroundStyle(tint)
            } minimal: {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(tint)
            }
            .keylineTint(tint)
        }
    }
}

/// Lock screen / banner presentation.
private struct StormActivityLockView: View {
    let snapshot: StormSnapshot
    let placeName: String

    private var tint: Color {
        snapshot.isImmediateDanger ? WidgetPalette.danger : WidgetPalette.accent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label {
                    Text(String(localized: "live.strikes",
                                defaultValue: "\(snapshot.strikeCount) Blitze · \(Int(snapshot.radiusKilometers)) km"))
                        .font(.headline)
                        .foregroundStyle(WidgetPalette.primaryText)
                } icon: {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(tint)
                }
                Spacer()
                Image(systemName: snapshot.trend.symbolName)
                    .foregroundStyle(WidgetPalette.secondaryText)
                    .accessibilityLabel(StormText.trend(snapshot.trend))
            }

            HStack(alignment: .firstTextBaseline) {
                Text(StormText.distance(snapshot))
                    .font(.title2.bold())
                    .foregroundStyle(tint)
                if let direction = snapshot.nearestBearingDegrees?.compassLabel {
                    Text(direction)
                        .font(.headline)
                        .foregroundStyle(WidgetPalette.secondaryText)
                }
                Spacer()
                if let eta = StormText.eta(snapshot) {
                    Text(eta)
                        .font(.subheadline)
                        .foregroundStyle(WidgetPalette.primaryText)
                }
            }

            if snapshot.isImmediateDanger {
                Text(StormText.shelter)
                    .font(.subheadline.bold())
                    .foregroundStyle(WidgetPalette.danger)
            }

            Label {
                Text(placeName)
                    .font(.caption)
                    .foregroundStyle(WidgetPalette.secondaryText)
            } icon: {
                Image(systemName: "location.fill")
                    .font(.caption2)
                    .foregroundStyle(WidgetPalette.secondaryText)
            }
        }
        .padding()
    }
}

/// Shared German strings for both widget surfaces.
enum StormText {
    static var shelter: String {
        String(localized: "live.shelter", defaultValue: "Sofort Schutz suchen!")
    }

    static func distance(_ snapshot: StormSnapshot) -> String {
        guard let meters = snapshot.nearestDistanceMeters else { return "–" }
        return meters.formattedDistance
    }

    static func eta(_ snapshot: StormSnapshot) -> String? {
        guard let seconds = snapshot.arrivalSeconds else { return nil }
        let minutes = max(1, Int((seconds / 60).rounded()))
        return String(localized: "live.eta", defaultValue: "Ankunft in ~\(minutes) min")
    }

    static func trend(_ trend: ActivityTrend) -> String {
        switch trend {
        case .rising: String(localized: "trend.rising", defaultValue: "Aktivität steigt")
        case .steady: String(localized: "trend.steady", defaultValue: "Aktivität gleichbleibend")
        case .falling: String(localized: "trend.falling", defaultValue: "Aktivität fällt")
        }
    }
}
