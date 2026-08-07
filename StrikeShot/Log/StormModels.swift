import Foundation
import SwiftData

/// One shooting session at a storm, from "begin" to "end".
@Model
final class StormSession {
    var id: UUID
    var start: Date
    var end: Date?
    var latitude: Double?
    var longitude: Double?
    var placeName: String
    var maxStrikeCount: Int
    var nearestStrikeMeters: Double?
    var peakIntensityRaw: Int
    @Relationship(deleteRule: .cascade, inverse: \CaptureRecord.session)
    var captures: [CaptureRecord]

    init(id: UUID = UUID(), start: Date = .now, point: GeoPoint? = nil, placeName: String = "") {
        self.id = id
        self.start = start
        self.end = nil
        self.latitude = point?.latitude
        self.longitude = point?.longitude
        self.placeName = placeName
        self.maxStrikeCount = 0
        self.nearestStrikeMeters = nil
        self.peakIntensityRaw = StormIntensity.calm.rawValue
        self.captures = []
    }

    var point: GeoPoint? {
        guard let latitude, let longitude else { return nil }
        return GeoPoint(latitude: latitude, longitude: longitude)
    }

    /// Open sessions measure up to now.
    var duration: TimeInterval { (end ?? .now).timeIntervalSince(start) }

    var peakIntensity: StormIntensity {
        get { StormIntensity(rawValue: peakIntensityRaw) ?? .calm }
        set { peakIntensityRaw = newValue.rawValue }
    }

    var displayName: String {
        placeName.isEmpty
            ? String(localized: "log.place.unknown", defaultValue: "Unbekannter Ort")
            : placeName
    }

    var sortedCaptures: [CaptureRecord] { captures.sorted { $0.date < $1.date } }

    var bestCapture: CaptureRecord? {
        captures.filter { $0.score > 0 }.max { $0.score < $1.score }
    }
}

/// One photo/video the camera took during a session.
@Model
final class CaptureRecord {
    var id: UUID
    var date: Date
    var modeRaw: String
    var fileURLString: String
    var photoLibraryIdentifier: String?
    var peakLuma: Double
    var thunderDistanceMeters: Double?
    @Attribute(.externalStorage) var thumbnail: Data?
    var score: Double
    var session: StormSession?

    init(result: CaptureResult) {
        self.id = result.id
        self.date = result.date
        self.modeRaw = result.mode.rawValue
        self.fileURLString = result.fileURL.absoluteString
        self.photoLibraryIdentifier = result.photoLibraryIdentifier
        self.peakLuma = result.peakLuma
        self.thunderDistanceMeters = result.thunderDistanceMeters
        self.thumbnail = result.thumbnailData
        self.score = 0
    }

    var mode: CaptureMode { CaptureMode(rawValue: modeRaw) ?? .photo }

    var fileURL: URL? { URL(string: fileURLString) }
}

/// Aggregated lifetime numbers. Pure value type so achievements stay unit-testable.
struct StormStats {
    struct HeatmapPoint: Identifiable, Hashable {
        var point: GeoPoint
        var weight: Int
        var id: String { "\(point.latitude):\(point.longitude)" }
    }

    var totalStrikesSeen = 0
    var totalSessions = 0
    var totalCaptures = 0
    var closestStrikeMeters: Double?
    /// Nearest measured thunder (from capture records), feeds the thunder achievement.
    var closestThunderMeters: Double?
    var longestSessionDuration: TimeInterval = 0
    var nightSessions = 0
    var slowMotionCaptures = 0
    var heatmapPoints: [HeatmapPoint] = []
}

extension TimeInterval {
    /// "1 h 24 min" style, locale-aware.
    var formattedSessionDuration: String {
        Duration.seconds(self).formatted(
            .units(allowed: [.hours, .minutes, .seconds], width: .narrow, maximumUnitCount: 2)
        )
    }
}
