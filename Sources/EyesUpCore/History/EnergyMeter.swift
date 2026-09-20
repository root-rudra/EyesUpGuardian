import Foundation

public struct EnergyTick: Equatable, Sendable {
    public var kilowattHours: Double
    public var awakeSeconds: TimeInterval
    /// The moment the interval ended; the day bucket is chosen from this.
    public var at: Date
}

/// Turns repeated power readings into energy. Gaps longer than `maxGap` are not integrated: the Mac
/// was asleep or the app wasn't sampling, and guessing would invent kilowatt-hours that never happened.
public struct EnergyMeter: Sendable {
    public static let maxGap: TimeInterval = 120
    /// No desktop Mac draws this much; a reading above it is a sensor fault, not electricity.
    public static let maxWatts = 2000.0

    private var lastTime: Date?

    public init() {}

    public mutating func accumulate(watts: Double, at now: Date, awake: Bool) -> EnergyTick? {
        defer { lastTime = now }
        guard watts.isFinite, watts >= 0, watts <= Self.maxWatts else { return nil }
        guard let last = lastTime else { return nil }
        let elapsed = now.timeIntervalSince(last)
        guard elapsed > 0, elapsed <= Self.maxGap else { return nil }

        let kilowattHours = watts * elapsed / 3_600_000
        return EnergyTick(kilowattHours: kilowattHours, awakeSeconds: awake ? elapsed : 0, at: now)
    }
}

public enum EnergyCost {
    /// Money for an amount of energy, or nil when there is no rate — the app never invents a figure.
    public static func money(_ kilowattHours: Double, ratePerKilowattHour: Double?, locale: Locale = .current) -> String? {
        guard let rate = ratePerKilowattHour, rate > 0, rate.isFinite,
              kilowattHours.isFinite, kilowattHours >= 0 else { return nil }
        let amount = kilowattHours * rate
        return amount.formatted(.currency(code: locale.currency?.identifier ?? "USD").locale(locale))
    }
}
