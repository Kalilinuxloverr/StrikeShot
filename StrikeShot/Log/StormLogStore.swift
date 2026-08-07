import CoreLocation
import Foundation
import SwiftData

/// Persists storm sessions and captures. Owns its own `ModelContainer` and
/// falls back to in-memory storage so a broken store never blocks the app.
@MainActor
@Observable
final class StormLogStore {
    let container: ModelContainer
    private(set) var activeSession: StormSession?
    private(set) var lastError: String?

    init() {
        let schema = Schema([StormSession.self, CaptureRecord.self])
        do {
            container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema))
        } catch {
            lastError = String(
                localized: "log.error.storage",
                defaultValue: "Tagebuch-Speicher konnte nicht geöffnet werden – neue Sessions gehen beim Beenden verloren."
            )
            do {
                container = try ModelContainer(
                    for: schema,
                    configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                )
            } catch {
                // ponytail: static schema, in-memory creation cannot realistically fail;
                // if SwiftData is this broken there is nothing left to fall back to.
                fatalError("SwiftData cannot create an in-memory container: \(error)")
            }
        }
        closeDanglingSessions()
    }

    func beginSession(at point: GeoPoint?, snapshot: StormSnapshot) {
        if activeSession != nil { endSession(snapshot: snapshot) }
        let session = StormSession(start: .now, point: point)
        session.maxStrikeCount = snapshot.strikeCount
        session.nearestStrikeMeters = snapshot.nearestDistanceMeters
        session.peakIntensity = snapshot.intensity
        container.mainContext.insert(session)
        activeSession = session
        save()
        if let point { resolvePlaceName(for: session, point: point) }
    }

    func endSession(snapshot: StormSnapshot) {
        guard let session = activeSession else { return }
        apply(snapshot, to: session)
        session.end = .now
        activeSession = nil
        save()
    }

    func record(_ result: CaptureResult, snapshot: StormSnapshot?) {
        let session: StormSession
        if let active = activeSession {
            session = active
        } else {
            // Capture arrived outside an explicit session — open one on the fly.
            beginSession(at: nil, snapshot: snapshot ?? StormSnapshot())
            guard let started = activeSession else { return }
            session = started
        }
        let record = CaptureRecord(result: result)
        container.mainContext.insert(record)
        record.session = session
        if let snapshot { apply(snapshot, to: session) }
        // ponytail: scoring runs synchronously on the main actor; the decode is
        // downsampled to <=1600 px so it stays cheap. Move to a background task
        // if profiling ever shows capture-time jank.
        let image = result.fileURL.isFileURL ? BestShotRanker.loadImage(at: result.fileURL) : nil
        if let image = image ?? result.thumbnailData.flatMap({ BestShotRanker.loadImage(data: $0) }) {
            record.score = BestShotRanker.score(image: image)
        }
        save()
    }

    func sessions() -> [StormSession] {
        do {
            return try container.mainContext.fetch(
                FetchDescriptor<StormSession>(sortBy: [SortDescriptor(\.start, order: .reverse)])
            )
        } catch {
            lastError = error.localizedDescription
            return []
        }
    }

    /// Recomputed from the store on every access.
    /// ponytail: full scan; cache behind a dirty flag if the diary ever gets huge.
    var stats: StormStats {
        var stats = StormStats()
        let calendar = Calendar.current
        var spots: [String: StormStats.HeatmapPoint] = [:]

        for session in sessions() {
            stats.totalSessions += 1
            stats.totalStrikesSeen += session.maxStrikeCount
            stats.totalCaptures += session.captures.count
            stats.longestSessionDuration = max(stats.longestSessionDuration, session.duration)
            if let nearest = session.nearestStrikeMeters {
                stats.closestStrikeMeters = min(stats.closestStrikeMeters ?? .infinity, nearest)
            }
            let hour = calendar.component(.hour, from: session.start)
            if hour >= 22 || hour < 5 { stats.nightSessions += 1 }
            for capture in session.captures {
                if capture.mode == .slowMotion { stats.slowMotionCaptures += 1 }
                if let thunder = capture.thunderDistanceMeters {
                    stats.closestThunderMeters = min(stats.closestThunderMeters ?? .infinity, thunder)
                }
            }
            if let point = session.point {
                // ~2 km bins so nearby sessions merge into one spot.
                let binned = GeoPoint(
                    latitude: (point.latitude * 50).rounded() / 50,
                    longitude: (point.longitude * 50).rounded() / 50
                )
                let key = "\(binned.latitude):\(binned.longitude)"
                var spot = spots[key] ?? StormStats.HeatmapPoint(point: binned, weight: 0)
                spot.weight += max(1, session.captures.count)
                spots[key] = spot
            }
        }
        stats.heatmapPoints = spots.values.sorted { $0.weight > $1.weight }
        return stats
    }

    // MARK: - Private

    private func apply(_ snapshot: StormSnapshot, to session: StormSession) {
        session.maxStrikeCount = max(session.maxStrikeCount, snapshot.strikeCount)
        if let nearest = snapshot.nearestDistanceMeters {
            session.nearestStrikeMeters = min(session.nearestStrikeMeters ?? .infinity, nearest)
        }
        session.peakIntensity = max(session.peakIntensity, snapshot.intensity)
    }

    private func save() {
        do {
            try container.mainContext.save()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Sessions left open by a crash or force-quit get closed at launch.
    private func closeDanglingSessions() {
        do {
            let open = try container.mainContext.fetch(
                FetchDescriptor<StormSession>(predicate: #Predicate { $0.end == nil })
            )
            guard !open.isEmpty else { return }
            for session in open {
                session.end = session.captures.map(\.date).max() ?? session.start
            }
            try container.mainContext.save()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func resolvePlaceName(for session: StormSession, point: GeoPoint) {
        Task { [weak self] in
            do {
                let location = CLLocation(latitude: point.latitude, longitude: point.longitude)
                let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
                if let name = placemarks.first?.locality ?? placemarks.first?.name {
                    session.placeName = name
                    self?.save()
                }
            } catch {
                // Expected offline; `displayName` falls back to a generic label.
            }
        }
    }
}
