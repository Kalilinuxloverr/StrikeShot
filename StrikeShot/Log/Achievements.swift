import Foundation

/// A lifetime badge. `isUnlocked` reads only `StormStats`, nothing else,
/// so every rule stays unit-testable without SwiftData.
struct Achievement: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbolName: String
    let isUnlocked: (StormStats) -> Bool

    static let all: [Achievement] = [
        Achievement(
            id: "first_session",
            title: String(localized: "achievement.firstSession.title", defaultValue: "Erster Sturm"),
            detail: String(localized: "achievement.firstSession.detail", defaultValue: "Die erste Session gestartet."),
            symbolName: "cloud.bolt.fill",
            isUnlocked: { $0.totalSessions >= 1 }
        ),
        Achievement(
            id: "strikes_10",
            title: String(localized: "achievement.strikes10.title", defaultValue: "Funkenflug"),
            detail: String(localized: "achievement.strikes10.detail", defaultValue: "10 Blitze gesehen."),
            symbolName: "bolt",
            isUnlocked: { $0.totalStrikesSeen >= 10 }
        ),
        Achievement(
            id: "strikes_100",
            title: String(localized: "achievement.strikes100.title", defaultValue: "Blitzsammler"),
            detail: String(localized: "achievement.strikes100.detail", defaultValue: "100 Blitze gesehen."),
            symbolName: "bolt.fill",
            isUnlocked: { $0.totalStrikesSeen >= 100 }
        ),
        Achievement(
            id: "strikes_1000",
            title: String(localized: "achievement.strikes1000.title", defaultValue: "Gewittergott"),
            detail: String(localized: "achievement.strikes1000.detail", defaultValue: "1000 Blitze gesehen."),
            symbolName: "bolt.circle.fill",
            isUnlocked: { $0.totalStrikesSeen >= 1_000 }
        ),
        Achievement(
            id: "first_capture",
            title: String(localized: "achievement.firstCapture.title", defaultValue: "Erster Schuss"),
            detail: String(localized: "achievement.firstCapture.detail", defaultValue: "Die erste Aufnahme im Kasten."),
            symbolName: "camera",
            isUnlocked: { $0.totalCaptures >= 1 }
        ),
        Achievement(
            id: "captures_25",
            title: String(localized: "achievement.captures25.title", defaultValue: "Serienjäger"),
            detail: String(localized: "achievement.captures25.detail", defaultValue: "25 Aufnahmen gesammelt."),
            symbolName: "camera.fill",
            isUnlocked: { $0.totalCaptures >= 25 }
        ),
        Achievement(
            id: "close_5km",
            title: String(localized: "achievement.close5km.title", defaultValue: "Nahe dran"),
            detail: String(localized: "achievement.close5km.detail", defaultValue: "Einen Einschlag näher als 5 km erlebt."),
            symbolName: "scope",
            isUnlocked: { ($0.closestStrikeMeters ?? .infinity) < 5_000 }
        ),
        Achievement(
            id: "thunder_3km",
            title: String(localized: "achievement.thunder3km.title", defaultValue: "Donnergrollen"),
            detail: String(localized: "achievement.thunder3km.detail", defaultValue: "Donner aus weniger als 3 km gemessen."),
            symbolName: "waveform",
            isUnlocked: { ($0.closestThunderMeters ?? .infinity) < 3_000 }
        ),
        Achievement(
            id: "night_hunter",
            title: String(localized: "achievement.nightHunter.title", defaultValue: "Nachtjäger"),
            detail: String(localized: "achievement.nightHunter.detail", defaultValue: "5 Sessions nach 22 Uhr gestartet."),
            symbolName: "moon.stars.fill",
            isUnlocked: { $0.nightSessions >= 5 }
        ),
        Achievement(
            id: "storms_5",
            title: String(localized: "achievement.storms5.title", defaultValue: "Sturmverfolger"),
            detail: String(localized: "achievement.storms5.detail", defaultValue: "5 Stürme verfolgt."),
            symbolName: "tornado",
            isUnlocked: { $0.totalSessions >= 5 }
        ),
        Achievement(
            id: "slomo_10",
            title: String(localized: "achievement.slomo10.title", defaultValue: "SloMo-Meister"),
            detail: String(localized: "achievement.slomo10.detail", defaultValue: "10 Zeitlupen-Aufnahmen gedreht."),
            symbolName: "slowmo",
            isUnlocked: { $0.slowMotionCaptures >= 10 }
        ),
        Achievement(
            id: "endurance",
            title: String(localized: "achievement.endurance.title", defaultValue: "Ausdauer"),
            detail: String(localized: "achievement.endurance.detail", defaultValue: "Eine Session von mindestens 2 Stunden."),
            symbolName: "timer",
            isUnlocked: { $0.longestSessionDuration >= 7_200 }
        ),
    ]
}
