import Foundation

/// Generates a plausible thunderstorm cell that drifts across the map and
/// scatters strikes around its moving center.
@MainActor
final class FeedSimulator {

    var onStrike: ((Strike) -> Void)?

    private var task: Task<Void, Never>?

    /// Starts a cell some 25–45 km out that drifts roughly toward `origin`.
    func start(around origin: GeoPoint) {
        stop()
        task = Task { [weak self] in
            let speed = Double.random(in: 6...13)
            var center = origin.projected(
                bearingDegrees: .random(in: 0..<360),
                meters: .random(in: 25_000...45_000)
            )
            var heading = center.bearing(to: origin) + .random(in: -20...20)

            // Seed 15 minutes of history so the tracker gets drift and ETA right away.
            let now = Date()
            for age in stride(from: 900.0, through: 30, by: -30) {
                let past = center.projected(bearingDegrees: heading + 180, meters: speed * age)
                self?.emit(around: past, time: now.addingTimeInterval(-age))
            }

            var lastTick = now
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: 0.6...2.5)))
                guard !Task.isCancelled, let self else { break }
                let tick = Date()
                center = center.projected(
                    bearingDegrees: heading,
                    meters: speed * tick.timeIntervalSince(lastTick)
                )
                heading += .random(in: -5...5)
                lastTick = tick
                self.emit(around: center, time: tick)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func emit(around center: GeoPoint, time: Date) {
        let point = center.projected(
            bearingDegrees: .random(in: 0..<360),
            meters: .random(in: 0...4_000)
        )
        onStrike?(Strike(point: point, time: time, quality: .random(in: 0.6...1)))
    }
}
