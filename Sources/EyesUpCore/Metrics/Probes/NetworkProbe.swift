import Foundation

/// Network throughput in and out, from the 64-bit interface counters.
public final class NetworkProbe {
    private let counters: any SystemCounters
    private let clock: any WallClock
    private var inMeter = RateMeter()
    private var outMeter = RateMeter()

    public init(counters: any SystemCounters = LiveSystemCounters(), clock: any WallClock = SystemClock()) {
        self.counters = counters
        self.clock = clock
    }

    public func resetBaseline() {
        inMeter = RateMeter()
        outMeter = RateMeter()
    }

    public func sample() -> NetworkMetrics? {
        let now = clock.now
        guard let split = counters.networkBytesSplit() else {
            // Only the combined counter is available; report it as inbound so the number isn't lost.
            guard let total = counters.networkBytes() else { return nil }
            return NetworkMetrics(inBytesPerSecond: inMeter.rate(for: total, at: now), outBytesPerSecond: nil)
        }
        return NetworkMetrics(
            inBytesPerSecond: inMeter.rate(for: split.received, at: now),
            outBytesPerSecond: outMeter.rate(for: split.sent, at: now)
        )
    }
}
