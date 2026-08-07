import Foundation

/// One detected lightning discharge.
struct Strike: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var point: GeoPoint
    var time: Date
    /// Detector confidence 0…1 where the source provides it.
    var quality: Double

    init(id: UUID = UUID(), point: GeoPoint, time: Date, quality: Double = 1) {
        self.id = id
        self.point = point
        self.time = time
        self.quality = quality
    }

    func age(at now: Date) -> TimeInterval { now.timeIntervalSince(time) }
}

/// How energetic a cell (or the whole radius) currently is. Drives the live theme.
enum StormIntensity: Int, Codable, Sendable, CaseIterable, Comparable {
    case calm, distant, active, severe

    static func < (lhs: StormIntensity, rhs: StormIntensity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Strikes per minute inside the watched radius.
    init(strikesPerMinute rate: Double) {
        switch rate {
        case ..<0.5: self = .calm
        case ..<4: self = .distant
        case ..<20: self = .active
        default: self = .severe
        }
    }

    var localizedName: String {
        switch self {
        case .calm: String(localized: "intensity.calm", defaultValue: "Ruhig")
        case .distant: String(localized: "intensity.distant", defaultValue: "Entfernt")
        case .active: String(localized: "intensity.active", defaultValue: "Aktiv")
        case .severe: String(localized: "intensity.severe", defaultValue: "Heftig")
        }
    }

    /// 0…1, used to scale accent brightness in the theme.
    var chargeLevel: Double {
        Double(rawValue) / Double(StormIntensity.allCases.count - 1)
    }
}

enum ActivityTrend: String, Codable, Sendable {
    case rising, steady, falling

    var symbolName: String {
        switch self {
        case .rising: "arrow.up.right"
        case .steady: "arrow.right"
        case .falling: "arrow.down.right"
        }
    }
}

/// A clustered thunderstorm cell with its drift.
struct StormCell: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var center: GeoPoint
    var strikeCount: Int
    var radiusMeters: Double
    /// Drift speed in m/s; nil until two time windows have been observed.
    var speedMetersPerSecond: Double?
    /// Direction of travel in degrees, 0 = north.
    var bearingDegrees: Double?
    var lastStrike: Date
    var intensity: StormIntensity

    init(
        id: UUID = UUID(),
        center: GeoPoint,
        strikeCount: Int,
        radiusMeters: Double,
        speedMetersPerSecond: Double? = nil,
        bearingDegrees: Double? = nil,
        lastStrike: Date,
        intensity: StormIntensity = .active
    ) {
        self.id = id
        self.center = center
        self.strikeCount = strikeCount
        self.radiusMeters = radiusMeters
        self.speedMetersPerSecond = speedMetersPerSecond
        self.bearingDegrees = bearingDegrees
        self.lastStrike = lastStrike
        self.intensity = intensity
    }

    /// Seconds until the cell edge reaches `target`, or nil if it is not closing in.
    /// ponytail: straight-line drift, no curvature or growth model.
    func timeToReach(_ target: GeoPoint) -> TimeInterval? {
        guard let speed = speedMetersPerSecond, speed > 0.5,
              let bearing = bearingDegrees else { return nil }
        let distance = center.distance(to: target) - radiusMeters
        guard distance > 0 else { return 0 }
        let bearingToTarget = center.bearing(to: target)
        var offBy = abs(bearingToTarget - bearing).truncatingRemainder(dividingBy: 360)
        if offBy > 180 { offBy = 360 - offBy }
        // More than ~50° off course means it passes by rather than arrives.
        guard offBy < 50 else { return nil }
        let closingSpeed = speed * cos(offBy * .pi / 180)
        guard closingSpeed > 0.5 else { return nil }
        return distance / closingSpeed
    }

    var isApproaching: Bool { (speedMetersPerSecond ?? 0) > 0.5 }
}

/// Everything the map, the widget and the Live Activity need in one value.
struct StormSnapshot: Hashable, Codable, Sendable {
    var strikeCount: Int
    var nearestDistanceMeters: Double?
    var nearestBearingDegrees: Double?
    var intensity: StormIntensity
    var trend: ActivityTrend
    var radiusKilometers: Double
    var updated: Date
    /// Seconds until the closest approaching cell arrives.
    var arrivalSeconds: TimeInterval?

    init(
        strikeCount: Int = 0,
        nearestDistanceMeters: Double? = nil,
        nearestBearingDegrees: Double? = nil,
        intensity: StormIntensity = .calm,
        trend: ActivityTrend = .steady,
        radiusKilometers: Double = 50,
        updated: Date = .distantPast,
        arrivalSeconds: TimeInterval? = nil
    ) {
        self.strikeCount = strikeCount
        self.nearestDistanceMeters = nearestDistanceMeters
        self.nearestBearingDegrees = nearestBearingDegrees
        self.intensity = intensity
        self.trend = trend
        self.radiusKilometers = radiusKilometers
        self.updated = updated
        self.arrivalSeconds = arrivalSeconds
    }

    static let placeholder = StormSnapshot()

    /// Lightning within 10 km means the next strike can hit here.
    var isDangerouslyClose: Bool {
        guard let distance = nearestDistanceMeters else { return false }
        return distance < 10_000
    }

    var isImmediateDanger: Bool {
        guard let distance = nearestDistanceMeters else { return false }
        return distance < 3_000
    }
}
