import Foundation
import SwiftUI

/// User preferences. One place, `UserDefaults`-backed, no schema, no migration.
@Observable
final class SettingsStore {
    private let defaults = UserDefaults.standard

    var radiusKilometers: Double {
        didSet { defaults.set(radiusKilometers, forKey: "radiusKilometers") }
    }

    /// 0 = only very bright flashes, 1 = hair trigger.
    var triggerSensitivity: Double {
        didSet { defaults.set(triggerSensitivity, forKey: "triggerSensitivity") }
    }

    var approachAlertsEnabled: Bool {
        didSet { defaults.set(approachAlertsEnabled, forKey: "approachAlertsEnabled") }
    }

    var safetyAlertsEnabled: Bool {
        didSet { defaults.set(safetyAlertsEnabled, forKey: "safetyAlertsEnabled") }
    }

    var thunderRangingEnabled: Bool {
        didSet { defaults.set(thunderRangingEnabled, forKey: "thunderRangingEnabled") }
    }

    var saveToPhotoLibrary: Bool {
        didSet { defaults.set(saveToPhotoLibrary, forKey: "saveToPhotoLibrary") }
    }

    var liveActivityEnabled: Bool {
        didSet { defaults.set(liveActivityEnabled, forKey: "liveActivityEnabled") }
    }

    /// Feed the map from the built-in simulator instead of the network.
    var useSimulatedFeed: Bool {
        didSet { defaults.set(useSimulatedFeed, forKey: "useSimulatedFeed") }
    }

    var hasSeenBootAnimation: Bool {
        didSet { defaults.set(hasSeenBootAnimation, forKey: "hasSeenBootAnimation") }
    }

    init() {
        defaults.register(defaults: [
            "radiusKilometers": 50.0,
            "triggerSensitivity": 0.5,
            "approachAlertsEnabled": true,
            "safetyAlertsEnabled": true,
            "thunderRangingEnabled": true,
            "saveToPhotoLibrary": true,
            "liveActivityEnabled": true,
            "useSimulatedFeed": false,
            "hasSeenBootAnimation": false,
        ])
        radiusKilometers = defaults.double(forKey: "radiusKilometers")
        triggerSensitivity = defaults.double(forKey: "triggerSensitivity")
        approachAlertsEnabled = defaults.bool(forKey: "approachAlertsEnabled")
        safetyAlertsEnabled = defaults.bool(forKey: "safetyAlertsEnabled")
        thunderRangingEnabled = defaults.bool(forKey: "thunderRangingEnabled")
        saveToPhotoLibrary = defaults.bool(forKey: "saveToPhotoLibrary")
        liveActivityEnabled = defaults.bool(forKey: "liveActivityEnabled")
        useSimulatedFeed = defaults.bool(forKey: "useSimulatedFeed")
        hasSeenBootAnimation = defaults.bool(forKey: "hasSeenBootAnimation")
    }
}
