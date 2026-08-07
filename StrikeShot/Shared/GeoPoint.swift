import CoreLocation
import Foundation

/// Codable, Hashable coordinate. `CLLocationCoordinate2D` is neither, and the
/// snapshot types travel through Live Activities and App Group storage.
struct GeoPoint: Hashable, Codable, Sendable {
    var latitude: Double
    var longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var isValid: Bool {
        latitude >= -90 && latitude <= 90 && longitude >= -180 && longitude <= 180
    }

    static let earthRadiusMeters = 6_371_000.0

    /// Great-circle distance in meters (haversine).
    func distance(to other: GeoPoint) -> Double {
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (other.longitude - longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * Self.earthRadiusMeters * atan2(sqrt(a), sqrt(max(0, 1 - a)))
    }

    /// Initial bearing in degrees, 0 = north, clockwise.
    func bearing(to other: GeoPoint) -> Double {
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let dLon = (other.longitude - longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let degrees = atan2(y, x) * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }

    /// Point reached by travelling `meters` along `bearingDegrees`.
    func projected(bearingDegrees: Double, meters: Double) -> GeoPoint {
        let angular = meters / Self.earthRadiusMeters
        let bearing = bearingDegrees * .pi / 180
        let lat1 = latitude * .pi / 180
        let lon1 = longitude * .pi / 180
        let lat2 = asin(sin(lat1) * cos(angular) + cos(lat1) * sin(angular) * cos(bearing))
        let lon2 = lon1 + atan2(
            sin(bearing) * sin(angular) * cos(lat1),
            cos(angular) - sin(lat1) * sin(lat2)
        )
        return GeoPoint(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
    }
}

extension Double {
    /// "3,2 km" / "780 m" in the user's locale.
    var formattedDistance: String {
        Measurement(value: self, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }

    /// Compass label for a bearing in degrees.
    var compassLabel: String {
        let points = ["N", "NO", "O", "SO", "S", "SW", "W", "NW"]
        let index = Int((self / 45).rounded())
        return points[((index % 8) + 8) % 8]
    }
}
