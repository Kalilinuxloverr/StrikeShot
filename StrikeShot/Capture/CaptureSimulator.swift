import Foundation

/// Deterministic synthetic luma feed: a dark, slightly noisy sky with occasional
/// lightning flashes that decay over ~0.2 s. Drives the trigger pipeline in unit
/// tests and on the iOS simulator, where there is no camera.
struct CaptureSimulator {
    /// Average flash rate; arrivals are Poisson-distributed.
    var flashesPerMinute: Double
    private(set) var flashCount = 0

    private var rng: SplitMix64
    private var lastTime: TimeInterval?
    private var flashStart: TimeInterval?
    private var flashPeak: Double = 0

    init(seed: UInt64 = 0x5EED_1337, flashesPerMinute: Double = 6) {
        self.flashesPerMinute = flashesPerMinute
        rng = SplitMix64(seed: seed)
    }

    /// Luma sample 0…1 for a monotonically increasing time.
    mutating func luma(at time: TimeInterval) -> Double {
        let dt = lastTime.map { max(time - $0, 0) } ?? 0
        lastTime = time

        if let start = flashStart, time - start > 0.4 {
            flashStart = nil
        }
        if flashStart == nil, dt > 0,
           Double.random(in: 0..<1, using: &rng) < flashesPerMinute / 60 * dt {
            flashStart = time
            flashPeak = Double.random(in: 0.7...1.0, using: &rng)
            flashCount += 1
        }

        let base = 0.07 + 0.02 * sin(time / 30)
        let noise = Double.random(in: -0.015...0.015, using: &rng)
        var value = base + noise
        if let start = flashStart {
            value = max(value, flashPeak * exp(-(time - start) / 0.08))
        }
        return min(max(value, 0), 1)
    }
}

/// Tiny deterministic RNG so simulator runs (and tests) are reproducible.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
