import MapKit
import SwiftUI

/// Live lightning map: strikes fade with age, cells show drift and ETA,
/// status on top, radius and simulator controls at the bottom.
struct MapScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(\.stormTheme) private var theme
    @State private var camera: MapCameraPosition = .automatic
    @State private var centeredOnUser = false

    // ponytail: hard cap on drawn markers, newest win — the map dies long before
    // the feed does. Upgrade path: clustering markers by zoom level.
    private static let maxDrawnStrikes = 250

    private var feed: LightningFeedController { services.feed }

    var body: some View {
        let now = Date()
        Map(position: $camera) {
            if let user = feed.userPoint {
                MapCircle(center: user.coordinate, radius: feed.radiusKilometers * 1_000)
                    .foregroundStyle(theme.accent.opacity(0.06))
                    .stroke(theme.accent.opacity(0.45), lineWidth: 1)
                Annotation(
                    String(localized: "map.you", defaultValue: "Du"),
                    coordinate: user.coordinate
                ) {
                    Circle()
                        .fill(theme.safe)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(theme.primaryText, lineWidth: 2))
                }
            }

            ForEach(drawnStrikes) { strike in
                let age = strike.age(at: now)
                Annotation("", coordinate: strike.point.coordinate) {
                    Circle()
                        .fill(theme.accent)
                        .frame(width: 7, height: 7)
                        .opacity(max(0.15, 1 - age / 1_800))
                        .shadow(color: theme.accentGlow.opacity(age < 120 ? 0.8 : 0), radius: 4)
                }
                .annotationTitles(.hidden)
            }

            ForEach(feed.cells) { cell in
                MapCircle(center: cell.center.coordinate, radius: cell.radiusMeters)
                    .foregroundStyle(theme.danger.opacity(0.10))
                    .stroke(theme.danger.opacity(0.55), lineWidth: 1.5)
                Annotation("", coordinate: cell.center.coordinate) {
                    cellBadge(for: cell)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .safeAreaInset(edge: .top) { statusBar }
        .safeAreaInset(edge: .bottom) { controls }
        .onAppear {
            camera = .region(region(around: feed.userPoint ?? LightningFeedController.fallbackPoint))
            centeredOnUser = feed.userPoint != nil
        }
        .onChange(of: feed.userPoint) { _, newValue in
            guard let point = newValue, !centeredOnUser else { return }
            centeredOnUser = true
            camera = .region(region(around: point))
        }
    }

    // MARK: - Map helpers

    private var drawnStrikes: [Strike] {
        let all = feed.strikes
        guard all.count > Self.maxDrawnStrikes else { return all }
        return Array(all.suffix(Self.maxDrawnStrikes)) // buffer is time-ordered
    }

    private func region(around point: GeoPoint) -> MKCoordinateRegion {
        let span = feed.radiusKilometers * 2_400
        return MKCoordinateRegion(
            center: point.coordinate,
            latitudinalMeters: span,
            longitudinalMeters: span
        )
    }

    @ViewBuilder
    private func cellBadge(for cell: StormCell) -> some View {
        VStack(spacing: 2) {
            if let bearing = cell.bearingDegrees, cell.isApproaching {
                Image(systemName: "location.north.fill")
                    .font(.caption)
                    .foregroundStyle(theme.danger)
                    .rotationEffect(.degrees(bearing))
            }
            if let label = etaLabel(for: cell) {
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(theme.primaryText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(theme.surface.opacity(0.85), in: Capsule())
            }
        }
    }

    private func etaLabel(for cell: StormCell) -> String? {
        guard let user = feed.userPoint, let seconds = cell.timeToReach(user) else { return nil }
        let minutes = max(1, Int((seconds / 60).rounded()))
        return String(localized: "map.cell.eta", defaultValue: "\(minutes) min")
    }

    // MARK: - Status bar

    private var statusBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Circle()
                    .fill(connectionColor)
                    .frame(width: 8, height: 8)
                Text(connectionLabel)
                    .font(.caption.weight(.medium))
                Spacer()
                Image(systemName: feed.snapshot.trend.symbolName)
                    .font(.caption)
                    .foregroundStyle(theme.accent)
                Text(feed.snapshot.intensity.localizedName)
                    .font(.caption.weight(.medium))
            }
            HStack {
                Text(String(
                    localized: "map.strikes.count",
                    defaultValue: "\(feed.snapshot.strikeCount) Blitze im Radius"
                ))
                Spacer()
                if let distance = feed.snapshot.nearestDistanceMeters,
                   let bearing = feed.snapshot.nearestBearingDegrees {
                    Text(String(
                        localized: "map.nearest",
                        defaultValue: "Nächster: \(distance.formattedDistance) \(bearing.compassLabel)"
                    ))
                }
            }
            .font(.caption)
            .foregroundStyle(theme.secondaryText)

            if case .failed(let reason) = feed.connection {
                failureBanner(reason)
            }
        }
        .foregroundStyle(theme.primaryText)
        .padding(12)
        .background(theme.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    private var connectionLabel: String {
        switch feed.connection {
        case .idle: String(localized: "feed.state.idle", defaultValue: "Bereit")
        case .connecting: String(localized: "feed.state.connecting", defaultValue: "Verbinde …")
        case .live: String(localized: "feed.state.live", defaultValue: "Live")
        case .simulated: String(localized: "feed.state.simulated", defaultValue: "Simulation")
        case .failed: String(localized: "feed.state.failed", defaultValue: "Getrennt")
        }
    }

    private var connectionColor: Color {
        switch feed.connection {
        case .live: theme.safe
        case .simulated: theme.accent
        case .connecting, .idle: theme.secondaryText
        case .failed: theme.danger
        }
    }

    private func failureBanner(_ reason: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(theme.danger)
            Text(reason)
                .font(.caption2)
                .lineLimit(2)
                .foregroundStyle(theme.secondaryText)
            Spacer()
            Button(String(localized: "feed.retry", defaultValue: "Wiederholen")) {
                feed.stop()
                feed.start()
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.borderedProminent)
            .tint(theme.accent)
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text(String(localized: "map.radius", defaultValue: "Radius"))
                Slider(
                    value: Binding(
                        get: { feed.radiusKilometers },
                        set: { feed.radiusKilometers = $0 }
                    ),
                    in: 10...250,
                    step: 5
                )
                .tint(theme.accent)
                Text(String(localized: "map.radius.value", defaultValue: "\(Int(feed.radiusKilometers)) km"))
                    .monospacedDigit()
                    .frame(width: 56, alignment: .trailing)
            }
            Toggle(
                String(localized: "map.simulator", defaultValue: "Simulator"),
                isOn: Binding(
                    get: { services.settings.useSimulatedFeed },
                    set: { feed.setSimulated($0) }
                )
            )
            .tint(theme.accent)
        }
        .font(.caption)
        .foregroundStyle(theme.primaryText)
        .padding(12)
        .background(theme.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}
