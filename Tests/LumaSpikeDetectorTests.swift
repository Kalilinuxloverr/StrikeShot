import XCTest
@testable import StrikeShot

final class LumaSpikeDetectorTests: XCTestCase {
    private let fps = 30.0

    /// Feeds 3 s of constant darkness so the baseline settles at `baseline`.
    private func warmedDetector(sensitivity: Double, baseline: Double = 0.1) -> LumaSpikeDetector {
        var detector = LumaSpikeDetector(sensitivity: sensitivity)
        for frame in 0..<Int(3 * fps) {
            _ = detector.ingest(luma: baseline, at: Double(frame) / fps)
        }
        return detector
    }

    func testSlowSunriseDriftDoesNotTrigger() {
        var detector = LumaSpikeDetector(sensitivity: 1)
        var triggers = 0
        for frame in 0..<Int(120 * fps) {
            let time = Double(frame) / fps
            let luma = 0.05 + 0.65 * time / 120
            if detector.ingest(luma: luma, at: time) { triggers += 1 }
        }
        XCTAssertEqual(triggers, 0)
        XCTAssertGreaterThan(detector.baseline, 0.6, "Baseline muss der Drift folgen")
    }

    func testSingleBrightSpikeTriggers() {
        var detector = warmedDetector(sensitivity: 0.5)
        XCTAssertTrue(detector.ingest(luma: 0.9, at: 3.0))
    }

    func testSpikes50msApartTriggerOnce() {
        var detector = warmedDetector(sensitivity: 0.5)
        var triggers = 0
        if detector.ingest(luma: 0.9, at: 3.0) { triggers += 1 }
        if detector.ingest(luma: 0.1, at: 3.0 + 1 / fps) { triggers += 1 }
        if detector.ingest(luma: 0.9, at: 3.05) { triggers += 1 }
        XCTAssertEqual(triggers, 1)
    }

    func testSpikes1sApartTriggerTwice() {
        var detector = warmedDetector(sensitivity: 0.5)
        var triggers = 0
        var time = 3.0
        if detector.ingest(luma: 0.9, at: time) { triggers += 1 }
        while time < 3.97 {
            time += 1 / fps
            if detector.ingest(luma: 0.1, at: time) { triggers += 1 }
        }
        if detector.ingest(luma: 0.9, at: 4.0) { triggers += 1 }
        XCTAssertEqual(triggers, 2)
    }

    func testHighSensitivityCatchesWeakSpikeLowDoesNot() {
        var eager = warmedDetector(sensitivity: 0.9)
        XCTAssertTrue(eager.ingest(luma: 0.28, at: 3.0))

        var stoic = warmedDetector(sensitivity: 0.1)
        XCTAssertFalse(stoic.ingest(luma: 0.28, at: 3.0))
    }

    func testDarkNoiseDoesNotTrigger() {
        var detector = LumaSpikeDetector(sensitivity: 1)
        var triggers = 0
        for frame in 0..<Int(30 * fps) {
            let time = Double(frame) / fps
            let luma = 0.05 + 0.02 * sin(Double(frame) * 1.7)
            if detector.ingest(luma: luma, at: time) { triggers += 1 }
        }
        XCTAssertEqual(triggers, 0)
    }
}
