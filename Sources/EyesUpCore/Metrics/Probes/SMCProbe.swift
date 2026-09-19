import Foundation

/// Power, fans and temperature from a curated key list.
///
/// Enumerating all 3,364 SMC keys costs 638 ms and reading all 209 temperature sensors costs 61 ms,
/// so the probe tries a fixed list once, keeps the keys that answer, and reads only those afterwards.
public final class SMCProbe {
    /// Whole-system power draw. `PSTR` answers on Apple Silicon desktops; the others are fallbacks.
    public static let powerKeys = ["PSTR", "PDTR", "PD0R"]
    /// Curated sensors: SoC clusters, then enclosure. The hottest readable one is reported.
    public static let temperatureKeys = ["Tp0T", "Tp1T", "Tp2T", "Tp3T", "Tp0o", "Tc02", "TVXs", "Te05", "TH0x"]
    public static let maxFans = 4

    private let smc: any SMCReading
    private var resolvedPowerKey: String?
    private var resolvedTemperatureKeys: [String]?
    private var resolvedFans: [(rpmKey: String, maxKey: String)]?
    private var probed = false

    public init(smc: any SMCReading) {
        self.smc = smc
    }

    /// True once any curated key has answered.
    public var isAvailable: Bool {
        resolveIfNeeded()
        return resolvedPowerKey != nil || !(resolvedTemperatureKeys ?? []).isEmpty || !(resolvedFans ?? []).isEmpty
    }

    public func power() -> PowerMetrics? {
        resolveIfNeeded()
        guard let key = resolvedPowerKey, let watts = smc.read(key), watts.isFinite, watts > 0, watts < 2000 else { return nil }
        return PowerMetrics(watts: watts)
    }

    public func temperature() -> TemperatureMetrics? {
        resolveIfNeeded()
        guard let keys = resolvedTemperatureKeys, !keys.isEmpty else { return nil }
        let readings = keys.compactMap { key -> Double? in
            guard let value = smc.read(key), Self.isPlausibleTemperature(value) else { return nil }
            return value
        }
        guard let hottest = readings.max() else { return nil }
        return TemperatureMetrics(celsius: hottest, sensorCount: readings.count)
    }

    public func fans() -> FanMetrics? {
        resolveIfNeeded()
        guard let resolved = resolvedFans, !resolved.isEmpty else { return nil }
        let readings = resolved.enumerated().compactMap { index, keys -> FanReading? in
            guard let rpm = smc.read(keys.rpmKey), rpm.isFinite, rpm >= 0, rpm < 20_000 else { return nil }
            let maximum = smc.read(keys.maxKey)
            return FanReading(index: index, rpm: rpm, maxRPM: maximum.flatMap { $0.isFinite && $0 > 0 ? $0 : nil })
        }
        return readings.isEmpty ? nil : FanMetrics(fans: readings)
    }

    private static func isPlausibleTemperature(_ value: Double) -> Bool {
        value.isFinite && value > 5 && value < 120
    }

    /// Tries the curated list once. Keys that don't answer are never asked again.
    private func resolveIfNeeded() {
        guard !probed else { return }
        probed = true
        resolvedPowerKey = Self.powerKeys.first { smc.read($0) != nil }
        resolvedTemperatureKeys = Self.temperatureKeys.filter { key in
            guard let value = smc.read(key) else { return false }
            return Self.isPlausibleTemperature(value)
        }
        let fanCount = smc.read("FNum").map { Int($0) } ?? 0
        resolvedFans = (0..<min(max(fanCount, 0), Self.maxFans)).compactMap { index in
            let rpmKey = "F\(index)Ac"
            guard smc.read(rpmKey) != nil else { return nil }
            return (rpmKey: rpmKey, maxKey: "F\(index)Mx")
        }
    }
}
