import Foundation
import SwiftUI

/// Wiring hub. Owns the long-lived controllers and connects them:
/// feed → theme, feed → alerts, feed → widget snapshot, capture → storm log.
///
/// Everything else in the app reads these through `@Environment(AppServices.self)`.
@MainActor
@Observable
final class AppServices {
    let settings: SettingsStore
    let theme = ThemeEngine()
    let feed: LightningFeedController
    let capture: CaptureController
    let log: StormLogStore
    let alerts: AlertEngine
    let liveActivity = LiveActivityController()

    private var started = false

    init() {
        let settings = SettingsStore()
        self.settings = settings
        feed = LightningFeedController(settings: settings)
        capture = CaptureController(settings: settings)
        log = StormLogStore()
        alerts = AlertEngine(settings: settings)
    }

    func start() async {
        guard !started else { return }
        started = true

        feed.onSnapshot = { [weak self] snapshot in
            guard let self else { return }
            self.theme.update(with: snapshot)
            SharedStore.write(snapshot)
            self.alerts.evaluate(snapshot: snapshot, cells: self.feed.cells)
            if self.settings.liveActivityEnabled {
                self.liveActivity.update(snapshot: snapshot, placeName: self.feed.placeName)
            }
        }

        capture.onCapture = { [weak self] result in
            guard let self else { return }
            self.log.record(result, snapshot: self.feed.snapshot)
        }

        await alerts.requestAuthorizationIfNeeded()
        feed.start()
    }

    /// Called when the capture screen opens/closes a shooting session.
    func beginStormSession() {
        log.beginSession(at: feed.userPoint, snapshot: feed.snapshot)
        if settings.liveActivityEnabled {
            liveActivity.start(snapshot: feed.snapshot, placeName: feed.placeName)
        }
    }

    func endStormSession() {
        log.endSession(snapshot: feed.snapshot)
        liveActivity.stop()
    }
}
