import Foundation

/// Pure flash detector over a scalar luma stream. No AVFoundation, fully testable.
///
/// An EMA baseline tracks slow ambient changes (sunrise, passing clouds). A frame
/// triggers when its rise above the baseline clears both a relative threshold
/// (bright daytime baselines) and an absolute floor (dark nights, sensor noise),
/// and the refractory window since the last trigger has passed. While the signal
/// is elevated the baseline is frozen so a flash cannot pull it up and mask itself.
struct LumaSpikeDetector {
    /// 0 = only very bright flashes, 1 = hair trigger.
    var sensitivity: Double

    private(set) var baseline: Double

    private var lastTime: TimeInterval?
    private var lastTrigger: TimeInterval?
    private var elevatedSince: TimeInterval?

    /// Seconds after a trigger during which no new trigger fires.
    static let refractoryInterval: TimeInterval = 0.25
    /// EMA time constant of the baseline.
    private static let baselineTau: TimeInterval = 1.5
    /// After this long above threshold the brightness counts as the new normal.
    private static let maxFreeze: TimeInterval = 1.0

    init(sensitivity: Double) {
        self.sensitivity = min(max(sensitivity, 0), 1)
        baseline = 0
    }

    /// Rise above the baseline required to trigger at the current sensitivity.
    var threshold: Double {
        let s = min(max(sensitivity, 0), 1)
        let absoluteFloor = 0.30 - 0.24 * s   // 0.30 … 0.06
        let relativeFactor = 1.2 - 0.9 * s    // 1.2 … 0.3 of the baseline
        return max(absoluteFloor, baseline * relativeFactor)
    }

    /// Returns true when this sample is a detected flash.
    mutating func ingest(luma: Double, at time: TimeInterval) -> Bool {
        let luma = min(max(luma, 0), 1)
        guard let last = lastTime else {
            lastTime = time
            baseline = luma
            return false
        }
        let dt = max(time - last, 0.001)
        lastTime = time

        let rise = luma - baseline
        let elevated = rise > threshold
        if elevated {
            if elevatedSince == nil { elevatedSince = time }
        } else {
            elevatedSince = nil
        }

        // Freeze the baseline during a spike; adopt after `maxFreeze` so a scene
        // that genuinely got brighter cannot deadlock the detector.
        let frozen = elevated && time - (elevatedSince ?? time) < Self.maxFreeze
        if !frozen {
            let alpha = 1 - exp(-dt / Self.baselineTau)
            baseline += (luma - baseline) * alpha
        }

        guard elevated else { return false }
        if let lastTrigger, time - lastTrigger < Self.refractoryInterval { return false }
        lastTrigger = time
        return true
    }

    mutating func reset() {
        lastTime = nil
        lastTrigger = nil
        elevatedSince = nil
        baseline = 0
    }
}
