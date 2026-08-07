import MapKit
import SwiftUI

/// Lifetime numbers, spot heatmap and the achievement grid.
struct StatsScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(\.stormTheme) private var theme
    @State private var stats = StormStats()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    tileGrid
                    heatmapSection
                    achievementsSection
                }
                .padding()
            }
            .background(theme.background.ignoresSafeArea())
            .navigationTitle(String(localized: "stats.title", defaultValue: "Statistik"))
        }
        // ponytail: stats recomputed only when the screen appears; observe the
        // store's save events if live updates are ever needed.
        .onAppear { stats = services.log.stats }
    }

    // MARK: - Tiles

    private var tileGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatTile(
                title: String(localized: "stats.sessions", defaultValue: "Sessions"),
                value: "\(stats.totalSessions)",
                symbolName: "cloud.bolt.fill"
            )
            StatTile(
                title: String(localized: "stats.strikes", defaultValue: "Blitze gesehen"),
                value: "\(stats.totalStrikesSeen)",
                symbolName: "bolt.fill"
            )
            StatTile(
                title: String(localized: "stats.captures", defaultValue: "Aufnahmen"),
                value: "\(stats.totalCaptures)",
                symbolName: "camera.fill"
            )
            StatTile(
                title: String(localized: "stats.closest", defaultValue: "Nächster Einschlag"),
                value: stats.closestStrikeMeters?.formattedDistance ?? "–",
                symbolName: "scope"
            )
            StatTile(
                title: String(localized: "stats.longest", defaultValue: "Längste Session"),
                value: stats.longestSessionDuration > 0
                    ? stats.longestSessionDuration.formattedSessionDuration
                    : "–",
                symbolName: "clock.fill"
            )
            StatTile(
                title: String(localized: "stats.night", defaultValue: "Nachtsessions"),
                value: "\(stats.nightSessions)",
                symbolName: "moon.stars.fill"
            )
            StatTile(
                title: String(localized: "stats.slomo", defaultValue: "SloMo-Aufnahmen"),
                value: "\(stats.slowMotionCaptures)",
                symbolName: "slowmo"
            )
            StatTile(
                title: String(localized: "stats.thunder", defaultValue: "Nächster Donner"),
                value: stats.closestThunderMeters?.formattedDistance ?? "–",
                symbolName: "waveform"
            )
        }
    }

    // MARK: - Heatmap

    private var heatmapSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "stats.heatmap.title", defaultValue: "Deine Spots"))
                .font(.title3.weight(.semibold))
                .foregroundStyle(theme.primaryText)
            if stats.heatmapPoints.isEmpty {
                Text(String(
                    localized: "stats.heatmap.empty",
                    defaultValue: "Sobald Sessions mit Standort aufgezeichnet sind, erscheinen deine Foto-Spots hier."
                ))
                .font(.subheadline)
                .foregroundStyle(theme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 16))
            } else {
                Map(initialPosition: .automatic) {
                    ForEach(stats.heatmapPoints) { spot in
                        MapCircle(center: spot.point.coordinate, radius: radius(for: spot.weight))
                            .foregroundStyle(theme.accent.opacity(opacity(for: spot.weight)))
                    }
                }
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private func radius(for weight: Int) -> Double {
        1_500 + Double(min(weight, 20)) * 300
    }

    private func opacity(for weight: Int) -> Double {
        min(0.55, 0.18 + Double(weight) * 0.04)
    }

    // MARK: - Achievements

    private var achievementsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "stats.achievements.title", defaultValue: "Erfolge"))
                .font(.title3.weight(.semibold))
                .foregroundStyle(theme.primaryText)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(Achievement.all) { achievement in
                    AchievementTile(achievement: achievement, isUnlocked: achievement.isUnlocked(stats))
                }
            }
        }
    }
}

private struct StatTile: View {
    @Environment(\.stormTheme) private var theme
    let title: String
    let value: String
    let symbolName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbolName)
                .font(.subheadline)
                .foregroundStyle(theme.accent)
            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct AchievementTile: View {
    @Environment(\.stormTheme) private var theme
    let achievement: Achievement
    let isUnlocked: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: achievement.symbolName)
                    .font(.title3)
                    .foregroundStyle(isUnlocked ? theme.accent : theme.secondaryText)
                    .shadow(
                        color: isUnlocked ? theme.accentGlow.opacity(0.6) : .clear,
                        radius: theme.glowRadius / 2
                    )
                Spacer()
                if !isUnlocked {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                }
            }
            Text(achievement.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isUnlocked ? theme.primaryText : theme.secondaryText)
            Text(achievement.detail)
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding()
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .opacity(isUnlocked ? 1 : 0.65)
    }
}
