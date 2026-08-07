import ActivityKit
import Foundation

/// Live Activity payload. Declared in Shared/ so app and widget agree on the shape.
struct StormActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var snapshot: StormSnapshot
    }

    var placeName: String
}

/// Snapshot hand-off from app to widget through the App Group.
///
/// ponytail: plain UserDefaults, no observation — the widget reloads its timeline
/// when the app writes. Without the App Group entitlement the suite is nil and
/// readers fall back to `.placeholder`, so the widget degrades instead of crashing.
enum SharedStore {
    static let appGroup = "group.dev.leonfrohlich.strikeshot"
    private static let snapshotKey = "storm.snapshot"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }

    static func write(_ snapshot: StormSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: snapshotKey)
    }

    static func read() -> StormSnapshot {
        guard let data = defaults?.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(StormSnapshot.self, from: data)
        else { return .placeholder }
        return snapshot
    }
}
