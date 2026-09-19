import Foundation

/// Turns a noisy measurement into a stable yes/no: on after `sustain` above the threshold,
/// off only after `release` below it, so brief spikes and dips don't flap the hold.
public struct ActivityGate: Sendable {
    public private(set) var isOn = false

    private let threshold: ActivityThreshold
    private var aboveSince: Date?
    private var belowSince: Date?

    public init(threshold: ActivityThreshold) {
        self.threshold = threshold
    }

    @discardableResult
    public mutating func update(value: Double, at now: Date) -> Bool {
        if value > threshold.value {
            belowSince = nil
            let since = aboveSince ?? now
            aboveSince = since
            if !isOn, now.timeIntervalSince(since) >= threshold.sustain { isOn = true }
        } else {
            aboveSince = nil
            let since = belowSince ?? now
            belowSince = since
            if isOn, now.timeIntervalSince(since) >= threshold.release { isOn = false }
        }
        return isOn
    }
}

/// Converts an ever-increasing counter into a per-second rate.
public struct RateMeter: Sendable {
    private var lastValue: UInt64?
    private var lastTime: Date?

    public init() {}

    /// nil on the first sample, when no time has passed, or when the counter went backwards (a reset).
    public mutating func rate(for value: UInt64, at now: Date) -> Double? {
        defer {
            lastValue = value
            lastTime = now
        }
        guard let lastValue, let lastTime, now > lastTime, value >= lastValue else { return nil }
        return Double(value - lastValue) / now.timeIntervalSince(lastTime)
    }
}

/// Converts cumulative CPU ticks into a busy percentage.
public struct CPUMeter: Sendable {
    private var last: (busy: UInt64, total: UInt64)?

    public init() {}

    public mutating func percent(busy: UInt64, total: UInt64) -> Double? {
        defer { last = (busy, total) }
        guard let last, total > last.total, busy >= last.busy else { return nil }
        return Double(busy - last.busy) / Double(total - last.total) * 100
    }
}
