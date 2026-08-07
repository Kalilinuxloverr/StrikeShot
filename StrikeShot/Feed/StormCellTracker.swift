import Foundation

/// Pure grid-based clustering of strikes into storm cells. No network, no UI.
struct StormCellTracker {

    /// Edge length of one clustering grid bucket.
    var gridSizeMeters: Double = 15_000

    private static let metersPerDegreeLatitude = 111_320.0
    private static let minimumRadiusMeters = 1_500.0
    private static let windowSeconds: TimeInterval = 600
    /// Minimum strikes per 10-minute window before drift is trusted.
    private static let minimumWindowStrikes = 3

    // ponytail: plain grid buckets — a cloud sitting on a bucket border splits in
    // two, and a cell crossing a border loses its drift history. Upgrade path:
    // match cells between runs by centroid proximity instead of bucket identity.
    func cells(from strikes: [Strike], now: Date) -> [StormCell] {
        var buckets: [GridKey: [Strike]] = [:]
        for strike in strikes {
            buckets[key(for: strike.point), default: []].append(strike)
        }
        return buckets
            .map { cell(for: $0.key, members: $0.value, now: now) }
            .sorted { $0.strikeCount > $1.strikeCount }
    }

    private struct GridKey: Hashable {
        var x: Int
        var y: Int
    }

    private func key(for point: GeoPoint) -> GridKey {
        let latMeters = point.latitude * Self.metersPerDegreeLatitude
        let lonMeters = point.longitude * Self.metersPerDegreeLatitude
            * cos(point.latitude * .pi / 180)
        return GridKey(
            x: Int(floor(lonMeters / gridSizeMeters)),
            y: Int(floor(latMeters / gridSizeMeters))
        )
    }

    private func cell(for key: GridKey, members: [Strike], now: Date) -> StormCell {
        let center = centroid(of: members.map(\.point))
        let radius = max(
            Self.minimumRadiusMeters,
            members.map { center.distance(to: $0.point) }.max() ?? 0
        )
        let lastStrike = members.map(\.time).max() ?? now

        let recent = members.filter { $0.age(at: now) <= Self.windowSeconds }
        let previous = members.filter {
            let age = $0.age(at: now)
            return age > Self.windowSeconds && age <= 2 * Self.windowSeconds
        }

        var speed: Double?
        var bearing: Double?
        if recent.count >= Self.minimumWindowStrikes,
           previous.count >= Self.minimumWindowStrikes {
            let from = centroid(of: previous.map(\.point))
            let to = centroid(of: recent.map(\.point))
            // Window centers sit one window length apart.
            speed = from.distance(to: to) / Self.windowSeconds
            bearing = from.bearing(to: to)
        }

        let ratePerMinute = Double(recent.count) / (Self.windowSeconds / 60)
        return StormCell(
            id: stableID(for: key),
            center: center,
            strikeCount: members.count,
            radiusMeters: radius,
            speedMetersPerSecond: speed,
            bearingDegrees: bearing,
            lastStrike: lastStrike,
            intensity: StormIntensity(strikesPerMinute: ratePerMinute)
        )
    }

    /// ponytail: naive lat/lon mean — wrong across the antimeridian, irrelevant
    /// for storm-sized clusters anywhere people use this app.
    private func centroid(of points: [GeoPoint]) -> GeoPoint {
        guard !points.isEmpty else { return GeoPoint(latitude: 0, longitude: 0) }
        let count = Double(points.count)
        return GeoPoint(
            latitude: points.reduce(0) { $0 + $1.latitude } / count,
            longitude: points.reduce(0) { $0 + $1.longitude } / count
        )
    }

    /// Deterministic UUID per grid bucket so SwiftUI identity survives recomputes.
    private func stableID(for key: GridKey) -> UUID {
        var uuid = uuid_t(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        withUnsafeMutableBytes(of: &uuid) { buffer in
            buffer.storeBytes(of: Int64(key.x).bigEndian, as: Int64.self)
            buffer.storeBytes(of: Int64(key.y).bigEndian, toByteOffset: 8, as: Int64.self)
        }
        return UUID(uuid: uuid)
    }
}
