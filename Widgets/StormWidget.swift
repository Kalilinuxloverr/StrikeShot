import SwiftUI
import WidgetKit

struct StormEntry: TimelineEntry {
    let date: Date
    let snapshot: StormSnapshot
}

struct StormProvider: TimelineProvider {
    func placeholder(in context: Context) -> StormEntry {
        StormEntry(date: .now, snapshot: .gallerySample)
    }

    func getSnapshot(in context: Context, completion: @escaping (StormEntry) -> Void) {
        // The gallery gets a lively sample; a real widget shows real data.
        let snapshot = context.isPreview ? StormSnapshot.gallerySample : SharedStore.read()
        completion(StormEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StormEntry>) -> Void) {
        // ponytail: single-entry timeline, refreshed every ~15 min; the app
        // triggers reloads on writes anyway. Add more entries if strike ages
        // ever need to tick down without an app in front.
        let entry = StormEntry(date: .now, snapshot: SharedStore.read())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60))))
    }
}

private extension StormSnapshot {
    /// Sample for the widget gallery so it never shows empty dashes.
    static let gallerySample = StormSnapshot(
        strikeCount: 23,
        nearestDistanceMeters: 12_400,
        nearestBearingDegrees: 225,
        intensity: .active,
        trend: .rising,
        radiusKilometers: 50,
        updated: .now,
        arrivalSeconds: 22 * 60
    )
}

struct StormWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StormWidget", provider: StormProvider()) { entry in
            StormWidgetView(entry: entry)
        }
        .configurationDisplayName(String(localized: "widget.name",
                                         defaultValue: "Gewitter-Radar"))
        .description(String(localized: "widget.description",
                            defaultValue: "Blitze im Umkreis, Entfernung des nächsten Einschlags und Trend."))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct StormWidgetView: View {
    let entry: StormEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if entry.snapshot.updated == .distantPast {
                // No App Group data yet (or no entitlement) — stay friendly.
                EmptyStormView()
            } else if family == .systemMedium {
                MediumStormView(snapshot: entry.snapshot)
            } else {
                SmallStormView(snapshot: entry.snapshot)
            }
        }
        .containerBackground(WidgetPalette.background, for: .widget)
    }
}

private struct EmptyStormView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "bolt.slash")
                .font(.title2)
                .foregroundStyle(WidgetPalette.secondaryText)
            Text(String(localized: "widget.empty",
                        defaultValue: "Noch keine Blitzdaten. Öffne StrikeShot, um das Radar zu starten."))
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(WidgetPalette.secondaryText)
        }
    }
}

private struct SmallStormView: View {
    let snapshot: StormSnapshot

    private var tint: Color {
        snapshot.isImmediateDanger ? WidgetPalette.danger : WidgetPalette.accent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(tint)
                Text("\(snapshot.strikeCount)")
                    .font(.title2.bold())
                    .foregroundStyle(WidgetPalette.primaryText)
                Spacer()
                Image(systemName: snapshot.trend.symbolName)
                    .foregroundStyle(WidgetPalette.secondaryText)
                    .accessibilityLabel(StormText.trend(snapshot.trend))
            }
            Spacer()
            if snapshot.nearestDistanceMeters != nil {
                HStack(spacing: 4) {
                    Text(StormText.distance(snapshot))
                        .font(.headline)
                        .foregroundStyle(tint)
                    if let direction = snapshot.nearestBearingDegrees?.compassLabel {
                        Text(direction)
                            .font(.subheadline)
                            .foregroundStyle(WidgetPalette.secondaryText)
                    }
                }
            } else {
                Text(String(localized: "widget.noStrikes",
                            defaultValue: "Keine Einschläge nah"))
                    .font(.caption)
                    .foregroundStyle(WidgetPalette.secondaryText)
            }
            Text(snapshot.intensity.localizedName)
                .font(.caption2)
                .foregroundStyle(WidgetPalette.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct MediumStormView: View {
    let snapshot: StormSnapshot

    private var tint: Color {
        snapshot.isImmediateDanger ? WidgetPalette.danger : WidgetPalette.accent
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(tint)
                    Text("\(snapshot.strikeCount)")
                        .font(.title.bold())
                        .foregroundStyle(WidgetPalette.primaryText)
                }
                Text(String(localized: "widget.radius",
                            defaultValue: "Umkreis \(Int(snapshot.radiusKilometers)) km"))
                    .font(.caption)
                    .foregroundStyle(WidgetPalette.secondaryText)
                HStack(spacing: 4) {
                    Image(systemName: snapshot.trend.symbolName)
                        .font(.caption)
                    Text(snapshot.intensity.localizedName)
                        .font(.caption)
                }
                .foregroundStyle(WidgetPalette.secondaryText)
                .accessibilityLabel(StormText.trend(snapshot.trend))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(String(localized: "widget.nearest",
                            defaultValue: "Nächster Einschlag"))
                    .font(.caption)
                    .foregroundStyle(WidgetPalette.secondaryText)
                HStack(spacing: 4) {
                    Text(StormText.distance(snapshot))
                        .font(.title3.bold())
                        .foregroundStyle(tint)
                    if let direction = snapshot.nearestBearingDegrees?.compassLabel {
                        Text(direction)
                            .font(.headline)
                            .foregroundStyle(WidgetPalette.secondaryText)
                    }
                }
                if let eta = StormText.eta(snapshot) {
                    Text(eta)
                        .font(.caption)
                        .foregroundStyle(WidgetPalette.primaryText)
                }
                Spacer()
                Text(snapshot.updated.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(WidgetPalette.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
