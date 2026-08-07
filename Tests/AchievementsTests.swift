import XCTest
@testable import StrikeShot

final class AchievementsTests: XCTestCase {

    // MARK: - Helpers

    private func achievement(_ id: String) throws -> Achievement {
        try XCTUnwrap(Achievement.all.first { $0.id == id }, "missing achievement \(id)")
    }

    private func stats(_ mutate: (inout StormStats) -> Void) -> StormStats {
        var stats = StormStats()
        mutate(&stats)
        return stats
    }

    private func assertThreshold(
        _ id: String,
        locked: StormStats,
        unlocked: StormStats,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let achievement = try achievement(id)
        XCTAssertFalse(achievement.isUnlocked(locked), "\(id) must stay locked just below threshold", file: file, line: line)
        XCTAssertTrue(achievement.isUnlocked(unlocked), "\(id) must unlock at threshold", file: file, line: line)
    }

    // MARK: - Baseline

    func testFreshStatsUnlockNothing() {
        let fresh = StormStats()
        for achievement in Achievement.all {
            XCTAssertFalse(achievement.isUnlocked(fresh), "\(achievement.id) must stay locked with fresh stats")
        }
    }

    func testAllIDsAreUniqueAndAtLeastTenExist() {
        let ids = Achievement.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "achievement ids must be unique")
        XCTAssertGreaterThanOrEqual(ids.count, 10)
    }

    // MARK: - Thresholds

    func testFirstSession() throws {
        try assertThreshold(
            "first_session",
            locked: stats { $0.totalSessions = 0 },
            unlocked: stats { $0.totalSessions = 1 }
        )
    }

    func testStrikes10() throws {
        try assertThreshold(
            "strikes_10",
            locked: stats { $0.totalStrikesSeen = 9 },
            unlocked: stats { $0.totalStrikesSeen = 10 }
        )
    }

    func testStrikes100() throws {
        try assertThreshold(
            "strikes_100",
            locked: stats { $0.totalStrikesSeen = 99 },
            unlocked: stats { $0.totalStrikesSeen = 100 }
        )
    }

    func testStrikes1000() throws {
        try assertThreshold(
            "strikes_1000",
            locked: stats { $0.totalStrikesSeen = 999 },
            unlocked: stats { $0.totalStrikesSeen = 1_000 }
        )
    }

    func testFirstCapture() throws {
        try assertThreshold(
            "first_capture",
            locked: stats { $0.totalCaptures = 0 },
            unlocked: stats { $0.totalCaptures = 1 }
        )
    }

    func testCaptures25() throws {
        try assertThreshold(
            "captures_25",
            locked: stats { $0.totalCaptures = 24 },
            unlocked: stats { $0.totalCaptures = 25 }
        )
    }

    func testCloseStrikeUnder5km() throws {
        // "closer than 5 km" is strict: exactly 5000 m stays locked.
        try assertThreshold(
            "close_5km",
            locked: stats { $0.closestStrikeMeters = 5_000 },
            unlocked: stats { $0.closestStrikeMeters = 4_999 }
        )
    }

    func testThunderUnder3km() throws {
        try assertThreshold(
            "thunder_3km",
            locked: stats { $0.closestThunderMeters = 3_000 },
            unlocked: stats { $0.closestThunderMeters = 2_999 }
        )
    }

    func testNightHunter() throws {
        try assertThreshold(
            "night_hunter",
            locked: stats { $0.nightSessions = 4 },
            unlocked: stats { $0.nightSessions = 5 }
        )
    }

    func testFiveStorms() throws {
        try assertThreshold(
            "storms_5",
            locked: stats { $0.totalSessions = 4 },
            unlocked: stats { $0.totalSessions = 5 }
        )
    }

    func testSloMoMaster() throws {
        try assertThreshold(
            "slomo_10",
            locked: stats { $0.slowMotionCaptures = 9 },
            unlocked: stats { $0.slowMotionCaptures = 10 }
        )
    }

    func testEndurance() throws {
        try assertThreshold(
            "endurance",
            locked: stats { $0.longestSessionDuration = 7_199 },
            unlocked: stats { $0.longestSessionDuration = 7_200 }
        )
    }
}
