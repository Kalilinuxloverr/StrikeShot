import XCTest
@testable import StrikeShot

final class StormCellTrackerTests: XCTestCase {

    private let tracker = StormCellTracker()
    private let now = Date(timeIntervalSince1970: 1_754_600_000)

    /// Deterministic ring of strikes around `center`. Coordinates sit near the
    /// equator, well inside a 15 km grid bucket, so bucket borders never split them.
    private func cloud(
        at center: GeoPoint,
        count: Int,
        spreadMeters: Double = 800,
        time: Date
    ) -> [Strike] {
        (0..<count).map { index in
            Strike(
                point: center.projected(
                    bearingDegrees: Double(index) * 360 / Double(count),
                    meters: spreadMeters
                ),
                time: time
            )
        }
    }

    // MARK: - Clustering

    func testFarApartCloudsFormTwoCellsTightCloudFormsOne() throws {
        let a = cloud(at: GeoPoint(latitude: 0.05, longitude: 0.05), count: 8, time: now.addingTimeInterval(-120))
        let b = cloud(at: GeoPoint(latitude: 0.05, longitude: 0.5), count: 5, time: now.addingTimeInterval(-60))

        XCTAssertEqual(tracker.cells(from: a + b, now: now).count, 2)

        let single = tracker.cells(from: a, now: now)
        XCTAssertEqual(single.count, 1)
        let cell = try XCTUnwrap(single.first)
        XCTAssertEqual(cell.strikeCount, 8)
        XCTAssertLessThan(cell.center.distance(to: GeoPoint(latitude: 0.05, longitude: 0.05)), 300)
        XCTAssertGreaterThanOrEqual(cell.radiusMeters, 700)
        XCTAssertEqual(cell.lastStrike, now.addingTimeInterval(-120))
    }

    func testEmptyInputYieldsNoCells() {
        XCTAssertTrue(tracker.cells(from: [], now: now).isEmpty)
    }

    // MARK: - Drift

    func testEastwardDriftYieldsBearing90AndPlausibleSpeed() throws {
        // Older window centroid at lon 0.03, newer at 0.07 → ~4.45 km east in 600 s.
        let older = cloud(at: GeoPoint(latitude: 0.05, longitude: 0.03), count: 6, time: now.addingTimeInterval(-700))
        let newer = cloud(at: GeoPoint(latitude: 0.05, longitude: 0.07), count: 6, time: now.addingTimeInterval(-100))

        let cells = tracker.cells(from: older + newer, now: now)
        XCTAssertEqual(cells.count, 1)
        let cell = try XCTUnwrap(cells.first)
        let speed = try XCTUnwrap(cell.speedMetersPerSecond)
        let bearing = try XCTUnwrap(cell.bearingDegrees)
        XCTAssertEqual(bearing, 90, accuracy: 5)
        XCTAssertEqual(speed, 7.4, accuracy: 1.5)
    }

    func testTooFewStrikesInOneWindowLeaveSpeedNil() throws {
        let older = cloud(at: GeoPoint(latitude: 0.05, longitude: 0.03), count: 2, time: now.addingTimeInterval(-700))
        let newer = cloud(at: GeoPoint(latitude: 0.05, longitude: 0.07), count: 6, time: now.addingTimeInterval(-100))

        let cell = try XCTUnwrap(tracker.cells(from: older + newer, now: now).first)
        XCTAssertNil(cell.speedMetersPerSecond)
        XCTAssertNil(cell.bearingDegrees)
    }

    // MARK: - ETA via StormCell.timeToReach

    func testApproachingCellHasPlausibleETAPassingCellHasNone() throws {
        let older = cloud(at: GeoPoint(latitude: 0.05, longitude: 0.03), count: 6, time: now.addingTimeInterval(-700))
        let newer = cloud(at: GeoPoint(latitude: 0.05, longitude: 0.07), count: 6, time: now.addingTimeInterval(-100))
        let cell = try XCTUnwrap(tracker.cells(from: older + newer, now: now).first)

        // ~50 km due east, straight ahead of the eastward drift.
        let ahead = GeoPoint(latitude: 0.05, longitude: 0.5)
        let eta = try XCTUnwrap(cell.timeToReach(ahead))
        let speed = try XCTUnwrap(cell.speedMetersPerSecond)
        let expected = (cell.center.distance(to: ahead) - cell.radiusMeters) / speed
        XCTAssertEqual(eta, expected, accuracy: expected * 0.2)
        XCTAssertGreaterThan(eta, 3_000)
        XCTAssertLessThan(eta, 12_000)

        // ~50 km due north: 90° off the drift course → it passes by.
        let aside = GeoPoint(latitude: 0.5, longitude: 0.05)
        XCTAssertNil(cell.timeToReach(aside))
    }
}
