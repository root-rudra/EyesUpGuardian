import Foundation

/// Free space on the boot volume, plus read/write rates from the block storage counters.
public final class StorageProbe {
    private let counters: any SystemCounters
    private let clock: any WallClock
    private var readMeter = RateMeter()
    private var writeMeter = RateMeter()

    public init(counters: any SystemCounters = LiveSystemCounters(), clock: any WallClock = SystemClock()) {
        self.counters = counters
        self.clock = clock
    }

    /// After a wake, the counters have jumped; start again rather than report a fake burst.
    public func resetBaseline() {
        readMeter = RateMeter()
        writeMeter = RateMeter()
    }

    public func sample() -> StorageMetrics? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]),
              let total = values.volumeTotalCapacity, total > 0 else { return nil }
        let free = UInt64(max(0, values.volumeAvailableCapacityForImportantUsage ?? 0))
        let now = clock.now
        let write = counters.diskBytesWritten().flatMap { writeMeter.rate(for: $0, at: now) }
        let read = counters.diskBytesRead().flatMap { readMeter.rate(for: $0, at: now) }
        return StorageMetrics(
            freeBytes: min(free, UInt64(total)),
            totalBytes: UInt64(total),
            readBytesPerSecond: read,
            writeBytesPerSecond: write
        )
    }
}
