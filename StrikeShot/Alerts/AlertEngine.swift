import Foundation
import Observation
import os
import UIKit
import UserNotifications

/// One user-facing storm warning.
struct StormAlert: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case approaching, danger, immediate, clearing
    }

    let id: UUID
    let kind: Kind
    let title: String
    let message: String
    let date: Date
}

/// Pure decision core, kept free of UNUserNotificationCenter so it is testable.
enum AlertDecider {
    static let debounceInterval: TimeInterval = 10 * 60
    static let approachWindow: TimeInterval = 30 * 60

    static func alert(
        snapshot: StormSnapshot,
        cells: [StormCell],
        userPoint: GeoPoint?,
        previous: StormAlert?,
        now: Date,
        approachEnabled: Bool = true,
        safetyEnabled: Bool = true
    ) -> StormAlert? {
        let approach = approachInfo(snapshot: snapshot, cells: cells, userPoint: userPoint)

        if let candidate = candidate(
            snapshot: snapshot,
            approach: approach,
            approachEnabled: approachEnabled,
            safetyEnabled: safetyEnabled,
            now: now
        ) {
            // Same or lower severity is debounced; a higher one fires immediately.
            if let previous,
               severity(candidate.kind) <= severity(previous.kind),
               now.timeIntervalSince(previous.date) < debounceInterval {
                return nil
            }
            return candidate
        }

        // Clearing: a warning was active and nothing is threatening any more.
        // Checked against the raw threat state, not the settings-filtered one,
        // so toggling alerts off never produces a bogus all-clear.
        let threatened = snapshot.isDangerouslyClose || approach != nil
        if !threatened, let previous, previous.kind != .clearing {
            return StormAlert(
                id: UUID(),
                kind: .clearing,
                title: String(localized: "alert.clearing.title",
                              defaultValue: "Gewitter zieht ab"),
                message: String(localized: "alert.clearing.message",
                                defaultValue: "Keine Blitze mehr in gefährlicher Nähe. Bleib trotzdem aufmerksam."),
                date: now
            )
        }
        return nil
    }

    private static func candidate(
        snapshot: StormSnapshot,
        approach: (eta: TimeInterval, bearingDegrees: Double?)?,
        approachEnabled: Bool,
        safetyEnabled: Bool,
        now: Date
    ) -> StormAlert? {
        if safetyEnabled, snapshot.isImmediateDanger {
            return StormAlert(
                id: UUID(),
                kind: .immediate,
                title: String(localized: "alert.immediate.title",
                              defaultValue: "Blitzeinschlag in unmittelbarer Nähe!"),
                message: String(localized: "alert.immediate.message",
                                defaultValue: "Geh sofort ins Haus oder ins Auto. Meide freie Flächen, Bäume und Wasser."),
                date: now
            )
        }
        if safetyEnabled, snapshot.isDangerouslyClose, let distance = snapshot.nearestDistanceMeters {
            return StormAlert(
                id: UUID(),
                kind: .danger,
                title: String(localized: "alert.danger.title",
                              defaultValue: "Gewitter gefährlich nah"),
                message: String(localized: "alert.danger.message",
                                defaultValue: "Einschlag nur \(distance.formattedDistance) entfernt. 30/30-Regel: Sind zwischen Blitz und Donner weniger als 30 Sekunden, such Schutz und bleib danach 30 Minuten drinnen."),
                date: now
            )
        }
        if approachEnabled, let approach {
            let minutes = max(1, Int((approach.eta / 60).rounded()))
            let message: String
            if let bearing = approach.bearingDegrees {
                message = String(localized: "alert.approaching.directed",
                                 defaultValue: "Gewitterzelle zieht aus \(bearing.compassLabel) heran – Ankunft in etwa \(minutes) Minuten.")
            } else {
                message = String(localized: "alert.approaching.plain",
                                 defaultValue: "Eine Gewitterzelle nähert sich – Ankunft in etwa \(minutes) Minuten.")
            }
            return StormAlert(
                id: UUID(),
                kind: .approaching,
                title: String(localized: "alert.approaching.title",
                              defaultValue: "Gewitter im Anzug"),
                message: message,
                date: now
            )
        }
        return nil
    }

    /// Closest approaching threat under 30 minutes: per-cell ETA when the user
    /// position is known, otherwise the feed's aggregate arrival estimate.
    private static func approachInfo(
        snapshot: StormSnapshot,
        cells: [StormCell],
        userPoint: GeoPoint?
    ) -> (eta: TimeInterval, bearingDegrees: Double?)? {
        var best: (eta: TimeInterval, bearingDegrees: Double?)?
        if let userPoint {
            for cell in cells {
                guard let eta = cell.timeToReach(userPoint), eta < approachWindow else { continue }
                if eta < (best?.eta ?? .infinity) {
                    best = (eta, userPoint.bearing(to: cell.center))
                }
            }
        }
        if best == nil, let eta = snapshot.arrivalSeconds, eta < approachWindow {
            best = (eta, snapshot.nearestBearingDegrees)
        }
        return best
    }

    private static func severity(_ kind: StormAlert.Kind) -> Int {
        switch kind {
        case .clearing: 0
        case .approaching: 1
        case .danger: 2
        case .immediate: 3
        }
    }
}

/// Runs the decider on every feed snapshot and turns its verdicts into
/// local notifications, haptics and in-app banners.
@MainActor
@Observable
final class AlertEngine {
    private(set) var lastAlert: StormAlert?
    private(set) var activeAlerts: [StormAlert] = []
    private(set) var authorizationDenied = false

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let logger = Logger(subsystem: "dev.leonfrohlich.strikeshot", category: "alerts")

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                authorizationDenied = !granted
            } catch {
                logger.error("Notification authorization failed: \(error.localizedDescription)")
                authorizationDenied = true
            }
        case .denied:
            authorizationDenied = true
        default:
            authorizationDenied = false
        }
    }

    func evaluate(snapshot: StormSnapshot, cells: [StormCell]) {
        // ponytail: userPoint is nil because AppServices does not hand it over;
        // approach detection rides on snapshot.arrivalSeconds instead. Wire the
        // feed's user location through here for per-cell direction accuracy.
        guard let alert = AlertDecider.alert(
            snapshot: snapshot,
            cells: cells,
            userPoint: nil,
            previous: lastAlert,
            now: .now,
            approachEnabled: settings.approachAlertsEnabled,
            safetyEnabled: settings.safetyAlertsEnabled
        ) else { return }

        lastAlert = alert
        if alert.kind == .clearing {
            activeAlerts.removeAll()
        } else {
            activeAlerts.removeAll { $0.kind == alert.kind }
        }
        activeAlerts.append(alert)
        deliver(alert)
    }

    func dismiss(_ alert: StormAlert) {
        // lastAlert stays untouched: it is the decider's debounce memory.
        activeAlerts.removeAll { $0.id == alert.id }
    }

    private func deliver(_ alert: StormAlert) {
        if alert.kind == .immediate {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }

        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.message
        // ponytail: .defaultCritical only pierces silent mode with the
        // critical-alerts entitlement; without it iOS plays the default sound.
        content.sound = alert.kind == .immediate ? .defaultCritical : .default
        content.interruptionLevel = alert.kind == .immediate ? .timeSensitive : .active

        let request = UNNotificationRequest(identifier: alert.id.uuidString, content: content, trigger: nil)
        Task {
            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                logger.error("Failed to deliver notification: \(error.localizedDescription)")
            }
        }
    }
}
