import CoreLocation
import Foundation

/// Wraps CLLocationManager and CLGeocoder. Emits the user's point and a nearby
/// place name; without permission it simply never emits — no crash, no error.
@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {

    var onPoint: ((GeoPoint) -> Void)?
    var onPlaceName: ((String) -> Void)?

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var lastGeocoded: GeoPoint?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 250
    }

    func start() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break // denied/restricted: the caller keeps its placeholder name
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        geocoder.cancelGeocode()
    }

    // MARK: - CLLocationManagerDelegate (delivered off-actor, hop to main)

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in self?.handleAuthorization(status) }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let latest = locations.last else { return }
        Task { @MainActor [weak self] in self?.handleUpdate(latest) }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        // Transient CLError (e.g. locationUnknown) is expected; the last known
        // point stays valid and the UI keeps its placeholder until a fix arrives.
    }

    // MARK: - Private

    private func handleAuthorization(_ status: CLAuthorizationStatus) {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    private func handleUpdate(_ location: CLLocation) {
        let point = GeoPoint(location.coordinate)
        guard point.isValid else { return }
        onPoint?(point)
        resolvePlaceName(for: point, location: location)
    }

    private func resolvePlaceName(for point: GeoPoint, location: CLLocation) {
        // Re-geocode only after moving a couple of kilometres.
        if let last = lastGeocoded, last.distance(to: point) < 2_000 { return }
        lastGeocoded = point
        Task { [weak self] in
            guard let self else { return }
            // Geocoding failure is cosmetic: the placeholder name stays.
            guard let placemark = try? await self.geocoder.reverseGeocodeLocation(location).first
            else { return }
            if let name = placemark.locality ?? placemark.subLocality ?? placemark.administrativeArea {
                self.onPlaceName?(name)
            }
        }
    }
}
