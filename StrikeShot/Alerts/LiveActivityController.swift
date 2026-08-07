import ActivityKit
import Foundation
import Observation
import os

/// Starts, updates and ends the storm Live Activity. Defensive by design:
/// every ActivityKit failure degrades to `isRunning = false` instead of crashing.
@MainActor
@Observable
final class LiveActivityController {
    private(set) var isRunning = false

    @ObservationIgnored private var activity: Activity<StormActivityAttributes>?
    @ObservationIgnored private var lastUpdate = Date.distantPast
    @ObservationIgnored private let logger = Logger(subsystem: "dev.leonfrohlich.strikeshot", category: "liveactivity")

    init() {}

    func start(snapshot: StormSnapshot, placeName: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            isRunning = false
            return
        }
        guard activity == nil else {
            update(snapshot: snapshot, placeName: placeName)
            return
        }
        do {
            activity = try Activity.request(
                attributes: StormActivityAttributes(placeName: placeName),
                content: content(for: snapshot)
            )
            lastUpdate = .now
            isRunning = true
        } catch {
            logger.error("Live Activity start failed: \(error.localizedDescription)")
            activity = nil
            isRunning = false
        }
    }

    func update(snapshot: StormSnapshot, placeName: String) {
        guard let activity else { return }
        // ponytail: hard 10 s throttle to respect the ActivityKit update budget;
        // switch to a trailing-edge coalescer if the final snapshot before a
        // lull must not be dropped.
        // ponytail: placeName lives in the immutable attributes, so a changed
        // name only shows after the next start(); restart the activity if that
        // ever matters.
        guard Date.now.timeIntervalSince(lastUpdate) >= 10 else { return }
        lastUpdate = .now
        let content = content(for: snapshot)
        Task {
            await activity.update(content)
        }
    }

    func stop() {
        isRunning = false
        guard let activity else { return }
        self.activity = nil
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func content(for snapshot: StormSnapshot) -> ActivityContent<StormActivityAttributes.ContentState> {
        ActivityContent(
            state: StormActivityAttributes.ContentState(snapshot: snapshot),
            staleDate: Date.now.addingTimeInterval(30 * 60)
        )
    }
}
