import Foundation
import Observation
import UIKit

/// Registers for remote pushes and mirrors token, position and watch radius to
/// the backend. The endpoint comes from the "pushEndpoint" UserDefaults key;
/// an empty or missing key means push is disabled — no network call, no error.
@MainActor
@Observable
final class PushRegistrar {
    static let shared = PushRegistrar()

    private(set) var deviceToken: String?
    private(set) var lastError: String?

    @ObservationIgnored private var lastPoint: GeoPoint?
    @ObservationIgnored private var lastRadiusKilometers: Double?

    private static let endpointKey = "pushEndpoint"

    func register() {
        guard endpointURL != nil else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// Entry point for the AppDelegate adapter below.
    static func received(deviceToken data: Data) {
        shared.deviceToken = data.map { String(format: "%02x", $0) }.joined()
        shared.lastError = nil
        shared.syncIfReady()
    }

    static func failed(_ error: Error) {
        shared.lastError = error.localizedDescription
    }

    /// Call whenever the user's position or the watch radius changes.
    func update(point: GeoPoint?, radiusKilometers: Double) {
        lastPoint = point
        lastRadiusKilometers = radiusKilometers
        syncIfReady()
    }

    private var endpointURL: URL? {
        guard let raw = UserDefaults.standard.string(forKey: Self.endpointKey),
              !raw.isEmpty,
              let url = URL(string: raw)
        else { return nil }
        return url
    }

    private func syncIfReady() {
        guard let url = endpointURL, let token = deviceToken else { return }

        struct Payload: Encodable {
            var token: String
            var latitude: Double?
            var longitude: Double?
            var radiusKilometers: Double?
        }
        let payload = Payload(
            token: token,
            latitude: lastPoint?.latitude,
            longitude: lastPoint?.longitude,
            radiusKilometers: lastRadiusKilometers
        )

        Task {
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONEncoder().encode(payload)
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    lastError = String(localized: "push.serverError",
                                       defaultValue: "Push-Server antwortete mit Status \(http.statusCode).")
                } else {
                    lastError = nil
                }
            } catch {
                lastError = error.localizedDescription
            }
        }
    }
}

/// Hook up in the app entry point via
/// `@UIApplicationDelegateAdaptor(PushAppDelegate.self)`.
@MainActor
final class PushAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        PushRegistrar.received(deviceToken: deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        PushRegistrar.failed(error)
    }
}
