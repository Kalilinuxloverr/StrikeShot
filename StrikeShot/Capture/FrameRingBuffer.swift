import Foundation

/// Bounded, thread-safe buffer of recent frames: evicts by age (relative to the
/// newest entry), by total cost in bytes, and by count — it never grows past its
/// caps, it drops the oldest frames instead. Generic so the eviction logic is
/// testable without constructing camera buffers; the capture pipeline stores its
/// deep-copied pixel buffers in it from the video callback queue.
final class FrameRingBuffer<Element> {
    struct Entry {
        let time: TimeInterval
        let cost: Int
        let element: Element
    }

    private let duration: TimeInterval
    private let maxTotalCost: Int
    private let maxCount: Int
    private let lock = NSLock()
    private var entries: [Entry] = []
    private var runningCost = 0

    // ponytail: 192 MB default ≈ 50 deep-copied 720p BGRA frames (~1.7 s at 30 fps).
    // Raise only together with a downscale step, or the app trips the jetsam limit.
    init(duration: TimeInterval = 3, maxTotalCost: Int = 192 * 1024 * 1024, maxCount: Int = 240) {
        self.duration = duration
        self.maxTotalCost = maxTotalCost
        self.maxCount = maxCount
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }

    var totalCost: Int {
        lock.lock()
        defer { lock.unlock() }
        return runningCost
    }

    func append(_ element: Element, time: TimeInterval, cost: Int) {
        lock.lock()
        defer { lock.unlock() }
        if let newest = entries.last, time < newest.time {
            // Timeline jumped backwards (session restart) — stale frames are useless.
            entries.removeAll()
            runningCost = 0
        }
        entries.append(Entry(time: time, cost: cost, element: element))
        runningCost += cost

        while let first = entries.first, time - first.time > duration {
            runningCost -= first.cost
            entries.removeFirst()
        }
        // ponytail: O(n) removeFirst on an Array; fine for a few hundred entries.
        while runningCost > maxTotalCost || entries.count > maxCount {
            guard !entries.isEmpty else { break }
            runningCost -= entries[0].cost
            entries.removeFirst()
        }
    }

    func snapshot() -> [Entry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
        runningCost = 0
    }
}
