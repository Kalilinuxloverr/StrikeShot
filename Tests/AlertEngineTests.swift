import XCTest
@testable import StrikeShot

/// Pure decider tests — no notifications, no ActivityKit.
final class AlertEngineTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_750_000_000)
    private let home = GeoPoint(latitude: 48.137, longitude: 11.575)

    private func snapshot(
        nearestMeters: Double? = nil,
        bearing: Double? = nil,
        arrivalSeconds: TimeInterval? = nil,
        intensity: StormIntensity = .active
    ) -> StormSnapshot {
        StormSnapshot(
            strikeCount: nearestMeters == nil ? 0 : 14,
            nearestDistanceMeters: nearestMeters,
            nearestBearingDegrees: bearing,
            intensity: intensity,
            trend: .steady,
            radiusKilometers: 50,
            updated: now,
            arrivalSeconds: arrivalSeconds
        )
    }

    private func previousAlert(kind: StormAlert.Kind, ageSeconds: TimeInterval) -> StormAlert {
        StormAlert(id: UUID(), kind: kind, title: "t", message: "m",
                   date: now.addingTimeInterval(-ageSeconds))
    }

    private func decide(
        _ snapshot: StormSnapshot,
        cells: [StormCell] = [],
        userPoint: GeoPoint? = nil,
        previous: StormAlert? = nil
    ) -> StormAlert? {
        AlertDecider.alert(
            snapshot: snapshot,
            cells: cells,
            userPoint: userPoint,
            previous: previous,
            now: now
        )
    }

    func testStrikeAtTwoKilometersTriggersImmediate() {
        let alert = decide(snapshot(nearestMeters: 2_000, bearing: 90))
        XCTAssertEqual(alert?.kind, .immediate)
    }

    func testStrikeAtSevenKilometersTriggersDanger() {
        let alert = decide(snapshot(nearestMeters: 7_000, bearing: 45))
        XCTAssertEqual(alert?.kind, .danger)
    }

    func testStrikeAtFortyKilometersWithoutApproachingCellTriggersNothing() {
        XCTAssertNil(decide(snapshot(nearestMeters: 40_000)))
    }

    func testApproachingCellWithTwelveMinuteETATriggersApproachingWithETAInText() {
        // Cell edge 10.8 km away, drifting straight at the user at 15 m/s -> 720 s.
        let center = home.projected(bearingDegrees: 0, meters: 12_000)
        let cell = StormCell(
            center: center,
            strikeCount: 30,
            radiusMeters: 1_200,
            speedMetersPerSecond: 15,
            bearingDegrees: 180,
            lastStrike: now
        )
        let alert = decide(snapshot(nearestMeters: 40_000), cells: [cell], userPoint: home)
        XCTAssertEqual(alert?.kind, .approaching)
        XCTAssertTrue(alert?.message.contains("12") == true,
                      "ETA in minutes must appear in the message, got: \(alert?.message ?? "nil")")
    }

    func testSameKindWithinTenMinutesIsSuppressedAndAllowedAfterEleven() {
        let recent = previousAlert(kind: .danger, ageSeconds: 5 * 60)
        XCTAssertNil(decide(snapshot(nearestMeters: 7_000), previous: recent))

        let old = previousAlert(kind: .danger, ageSeconds: 11 * 60)
        XCTAssertEqual(decide(snapshot(nearestMeters: 7_000), previous: old)?.kind, .danger)
    }

    func testImmediateOverridesTwoMinuteOldDanger() {
        let recentDanger = previousAlert(kind: .danger, ageSeconds: 2 * 60)
        let alert = decide(snapshot(nearestMeters: 2_000), previous: recentDanger)
        XCTAssertEqual(alert?.kind, .immediate)
    }

    func testQuietAfterActiveAlertTriggersClearingExactlyOnce() {
        let calm = snapshot(intensity: .calm)
        let previous = previousAlert(kind: .danger, ageSeconds: 12 * 60)
        XCTAssertEqual(decide(calm, previous: previous)?.kind, .clearing)

        // A clearing alert never repeats itself.
        let cleared = previousAlert(kind: .clearing, ageSeconds: 2 * 60)
        XCTAssertNil(decide(calm, previous: cleared))
    }

    func testDisabledSettingsSuppressTheirKinds() {
        let noSafety = AlertDecider.alert(
            snapshot: snapshot(nearestMeters: 2_000),
            cells: [], userPoint: nil, previous: nil, now: now,
            approachEnabled: true, safetyEnabled: false
        )
        XCTAssertNil(noSafety)

        let noApproach = AlertDecider.alert(
            snapshot: snapshot(arrivalSeconds: 12 * 60),
            cells: [], userPoint: nil, previous: nil, now: now,
            approachEnabled: false, safetyEnabled: true
        )
        XCTAssertNil(noApproach)
    }
}
