import XCTest
@testable import StrikeShot

final class CaptureSupportTests: XCTestCase {
    // MARK: - FrameRingBuffer

    func testRingBufferEvictsByAge() {
        let ring = FrameRingBuffer<Int>(duration: 3, maxTotalCost: .max, maxCount: .max)
        for index in 0..<200 {
            ring.append(index, time: Double(index) * 0.1, cost: 1)
        }
        let entries = ring.snapshot()
        guard let first = entries.first, let last = entries.last else {
            return XCTFail("Puffer ist leer")
        }
        XCTAssertEqual(last.time, 19.9, accuracy: 0.001)
        XCTAssertLessThanOrEqual(last.time - first.time, 3.0001, "Fenster größer als duration")
        XCTAssertGreaterThanOrEqual(entries.count, 29, "Zu viel verworfen")
    }

    func testRingBufferEnforcesCostCap() {
        let ring = FrameRingBuffer<Int>(duration: 1000, maxTotalCost: 50, maxCount: .max)
        for index in 0..<20 {
            ring.append(index, time: Double(index), cost: 10)
        }
        XCTAssertLessThanOrEqual(ring.totalCost, 50)
        XCTAssertEqual(ring.snapshot().map(\.element), [15, 16, 17, 18, 19])
    }

    func testRingBufferEnforcesCountCap() {
        let ring = FrameRingBuffer<Int>(duration: 1000, maxTotalCost: .max, maxCount: 4)
        for index in 0..<10 {
            ring.append(index, time: Double(index), cost: 1)
        }
        XCTAssertEqual(ring.snapshot().map(\.element), [6, 7, 8, 9])
    }

    func testRingBufferRemoveAll() {
        let ring = FrameRingBuffer<Int>()
        ring.append(1, time: 0, cost: 8)
        ring.removeAll()
        XCTAssertEqual(ring.count, 0)
        XCTAssertEqual(ring.totalCost, 0)
    }

    // MARK: - CaptureSimulator

    func testSimulatorYieldsPlausibleTriggerCountOverOneMinute() {
        var simulator = CaptureSimulator(seed: 42, flashesPerMinute: 8)
        var detector = LumaSpikeDetector(sensitivity: 0.5)
        var triggers = 0
        let fps = 30.0
        for frame in 0..<Int(60 * fps) {
            let time = Double(frame) / fps
            if detector.ingest(luma: simulator.luma(at: time), at: time) {
                triggers += 1
            }
        }
        XCTAssertTrue((2...20).contains(triggers), "Unplausible Trigger-Anzahl: \(triggers)")
        XCTAssertLessThanOrEqual(abs(triggers - simulator.flashCount), 1,
                                 "\(triggers) Trigger bei \(simulator.flashCount) Blitzen")
    }
}
