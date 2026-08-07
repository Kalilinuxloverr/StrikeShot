import Foundation
import Observation

enum FeedConnectionState: Equatable {
    case idle
    case connecting
    case live
    case simulated
    case failed(String)
}

/// Owns the strike buffer, clustering and throttled snapshot publishing.
@MainActor
@Observable
final class LightningFeedController {

    var onSnapshot: ((StormSnapshot) -> Void)?

    private(set) var strikes: [Strike] = []
    private(set) var cells: [StormCell] = []
    private(set) var snapshot: StormSnapshot = .placeholder
    private(set) var connection: FeedConnectionState = .idle
    private(set) var userPoint: GeoPoint?
    private(set) var placeName: String

    /// Mirrors `settings.radiusKilometers` and writes back on set.
    var radiusKilometers: Double {
        get { settings.radiusKilometers }
        set {
            settings.radiusKilometers = min(max(newValue, 10), 250)
            scheduleRecompute()
        }
    }

    /// Reference for the map and the simulator before a location fix (central Europe).
    static let fallbackPoint = GeoPoint(latitude: 50.0, longitude: 10.0)

    private static let maxStrikeAgeSeconds: TimeInterval = 3_600
    private static let maxBufferedStrikes = 5_000
    // ponytail: strikes farther than this from the reference are dropped on
    // ingest even though the user may move later; reset the buffer on big
    // location jumps if that ever matters.
    private static let bufferRadiusMeters = 300_000.0
    private static let publishIntervalSeconds: TimeInterval = 2

    private let settings: SettingsStore
    private let location = LocationProvider()
    private let tracker = StormCellTracker()

    @ObservationIgnored private var client: BlitzortungClient?
    @ObservationIgnored private var simulator: FeedSimulator?
    @ObservationIgnored private var feedTask: Task<Void, Never>?
    @ObservationIgnored private var tickerTask: Task<Void, Never>?
    @ObservationIgnored private var recomputeTask: Task<Void, Never>?
    @ObservationIgnored private var buffer: [Strike] = []
    @ObservationIgnored private var lastRecompute = Date.distantPast
    @ObservationIgnored private var isRunning = false

    init(settings: SettingsStore) {
        self.settings = settings
        self.placeName = String(localized: "feed.place.unknown", defaultValue: "Standort unbekannt")
        location.onPoint = { [weak self] point in
            guard let self else { return }
            self.userPoint = point
            self.scheduleRecompute()
        }
        location.onPlaceName = { [weak self] name in
            self?.placeName = name
        }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        location.start()
        if settings.useSimulatedFeed {
            startSimulator()
        } else {
            startLive()
        }
        // Periodic tick so counts and intensity decay after the storm passes.
        tickerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, let self else { break }
                if !self.buffer.isEmpty || self.snapshot.strikeCount > 0 {
                    self.scheduleRecompute()
                }
            }
        }
    }

    func stop() {
        isRunning = false
        stopSource()
        tickerTask?.cancel()
        tickerTask = nil
        location.stop()
        connection = .idle
    }

    func setSimulated(_ on: Bool) {
        settings.useSimulatedFeed = on
        guard isRunning else { return }
        stopSource()
        if on {
            startSimulator()
        } else {
            startLive()
        }
    }

    // MARK: - Sources

    private func startLive() {
        connection = .connecting
        let client = BlitzortungClient()
        self.client = client
        client.onStatus = { [weak self] status in
            Task { @MainActor [weak self] in
                guard let self, self.client === client else { return }
                switch status {
                case .connecting:
                    // Keep a visible failure until data actually flows again.
                    if case .failed = self.connection { break }
                    self.connection = .connecting
                case .connected:
                    self.connection = .live
                case .failed(let reason):
                    self.connection = .failed(reason)
                }
            }
        }
        feedTask = Task { [weak self] in
            for await strike in client.strikes() {
                self?.ingest(strike)
            }
        }
    }

    private func startSimulator() {
        connection = .simulated
        let simulator = FeedSimulator()
        self.simulator = simulator
        simulator.onStrike = { [weak self] strike in
            self?.ingest(strike)
        }
        simulator.start(around: userPoint ?? Self.fallbackPoint)
    }

    private func stopSource() {
        feedTask?.cancel()
        feedTask = nil
        client?.stop()
        client = nil
        simulator?.stop()
        simulator = nil
        recomputeTask?.cancel()
        recomputeTask = nil
    }

    // MARK: - Pipeline

    private var referencePoint: GeoPoint { userPoint ?? Self.fallbackPoint }

    private func ingest(_ strike: Strike) {
        guard isRunning, strike.point.isValid,
              strike.point.distance(to: referencePoint) <= Self.bufferRadiusMeters
        else { return }
        buffer.append(strike)
        if simulator == nil, connection != .live {
            connection = .live // data is flowing, clear connecting/failed
        }
        scheduleRecompute()
    }

    /// Publishes at most every ~2 s no matter how fast strikes arrive.
    private func scheduleRecompute() {
        guard recomputeTask == nil else { return }
        let wait = max(0, Self.publishIntervalSeconds - Date().timeIntervalSince(lastRecompute))
        recomputeTask = Task { [weak self] in
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard let self, !Task.isCancelled else { return }
            self.recomputeTask = nil
            self.recompute()
        }
    }

    private func recompute() {
        let now = Date()
        lastRecompute = now

        buffer.removeAll { $0.age(at: now) > Self.maxStrikeAgeSeconds }
        if buffer.count > Self.maxBufferedStrikes {
            buffer.removeFirst(buffer.count - Self.maxBufferedStrikes)
        }

        let reference = referencePoint
        let radiusMeters = radiusKilometers * 1_000
        let inRadius = buffer.filter { $0.point.distance(to: reference) <= radiusMeters }
        strikes = inRadius
        cells = tracker.cells(from: inRadius, now: now)

        var nearestDistance: Double?
        var nearestBearing: Double?
        if let nearest = inRadius.min(by: {
            $0.point.distance(to: reference) < $1.point.distance(to: reference)
        }) {
            nearestDistance = reference.distance(to: nearest.point)
            nearestBearing = reference.bearing(to: nearest.point)
        }

        let recentCount = inRadius.filter { $0.age(at: now) <= 300 }.count
        let previousCount = inRadius.filter {
            let age = $0.age(at: now)
            return age > 300 && age <= 600
        }.count
        let trend: ActivityTrend
        if recentCount > previousCount + max(2, previousCount / 4) {
            trend = .rising
        } else if previousCount > recentCount + max(2, recentCount / 4) {
            trend = .falling
        } else {
            trend = .steady
        }

        snapshot = StormSnapshot(
            strikeCount: inRadius.count,
            nearestDistanceMeters: nearestDistance,
            nearestBearingDegrees: nearestBearing,
            intensity: StormIntensity(strikesPerMinute: Double(recentCount) / 5),
            trend: trend,
            radiusKilometers: radiusKilometers,
            updated: now,
            arrivalSeconds: cells.compactMap { $0.timeToReach(reference) }.min()
        )
        onSnapshot?(snapshot)
    }
}
