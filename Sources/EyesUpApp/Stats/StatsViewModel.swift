import EyesUpCore
import Foundation
import Observation

/// One surface's claim on the metrics it displays. `start()` on appear, `stop()` on disappear —
/// that is what keeps sampling tied to what's actually visible (spec §6.1).
@MainActor
@Observable
final class StatsViewModel {
    struct StatTileModel: Identifiable {
        let id: String
        let title: String
        let value: String
        let detail: String
        let symbol: String
    }

    private let center: MetricsCenter
    private let ids: Set<MetricID>
    private(set) var interval: TimeInterval
    @ObservationIgnored private var subscription: MetricsSubscription?

    init(center: MetricsCenter, ids: Set<MetricID>, interval: TimeInterval) {
        self.center = center
        self.ids = ids
        self.interval = interval
    }

    var snapshot: MetricsSnapshot { center.snapshot }

    func history(_ id: MetricID) -> [Double] { center.history(id) }

    func start() {
        guard subscription == nil else { return }
        subscription = center.subscribe(ids, interval: interval)
    }

    func stop() {
        subscription?.cancel()
        subscription = nil
    }

    /// Changes how often this surface samples, resubscribing only if it is already running.
    func setInterval(_ newInterval: TimeInterval) {
        guard newInterval != interval else { return }
        interval = newInterval
        guard subscription != nil else { return }
        subscription?.cancel()
        subscription = center.subscribe(ids, interval: newInterval)
    }

    /// The popover's four tiles: CPU, memory, power (temperature when watts aren't readable), uptime.
    var tiles: [StatTileModel] {
        let snapshot = center.snapshot
        // A zero total means the reading failed; showing 0% would be a fake number.
        let memoryPercent = snapshot.memory.flatMap { $0.totalBytes > 0 ? Double($0.usedBytes) / Double($0.totalBytes) * 100 : nil }
        let powerTile: StatTileModel = if snapshot.power != nil || snapshot.temperature == nil {
            StatTileModel(id: "power", title: "Power", value: StatFormatting.watts(snapshot.power?.watts),
                          detail: "system", symbol: "bolt")
        } else {
            StatTileModel(id: "temperature", title: "Temp", value: StatFormatting.celsius(snapshot.temperature?.celsius),
                          detail: "hottest sensor", symbol: "thermometer.medium")
        }
        return [
            StatTileModel(id: "cpu", title: "CPU", value: StatFormatting.percent(snapshot.cpu?.total),
                          detail: snapshot.cpu.map { "\($0.cores.count) cores" } ?? "", symbol: "cpu"),
            StatTileModel(id: "memory", title: "Memory", value: StatFormatting.percent(memoryPercent),
                          detail: StatFormatting.bytes(snapshot.memory?.usedBytes), symbol: "memorychip"),
            powerTile,
            StatTileModel(id: "uptime", title: "Uptime", value: StatFormatting.uptime(since: snapshot.system?.bootTime),
                          detail: "since boot", symbol: "clock.arrow.circlepath"),
        ]
    }

    /// The menu-bar suffix, e.g. "12% · 38.4 W". Stats that aren't readable are left out entirely.
    /// Stats for the menu bar, each held at a fixed width so the item — and every icon beside it —
    /// stays put as the numbers change. See `MenuBarTitle.padded`.
    func readoutText(for readout: MenuBarReadout) -> String {
        var parts: [String] = []
        if readout.metricIDs.contains(.cpu), let cpu = snapshot.cpu {
            parts.append(MenuBarTitle.padded(StatFormatting.percent(cpu.total), to: 4))
        }
        if readout.metricIDs.contains(.memory), let memory = snapshot.memory {
            parts.append(MenuBarTitle.padded(StatFormatting.bytes(memory.usedBytes), to: 7))
        }
        if readout.metricIDs.contains(.power), let power = snapshot.power {
            parts.append(MenuBarTitle.padded(StatFormatting.watts(power.watts), to: 6))
        }
        if readout.metricIDs.contains(.temperature), let temperature = snapshot.temperature {
            parts.append(MenuBarTitle.padded(StatFormatting.celsius(temperature.celsius), to: 5))
        }
        if readout.metricIDs.contains(.network), let network = snapshot.network {
            parts.append(MenuBarTitle.padded("↓" + StatFormatting.rate(network.inBytesPerSecond), to: 10))
        }
        // A readout that promised a stat says so plainly when this Mac can't answer.
        if parts.isEmpty, !readout.metricIDs.isEmpty { return StatFormatting.unavailable }
        return parts.joined(separator: " · ")
    }
}
