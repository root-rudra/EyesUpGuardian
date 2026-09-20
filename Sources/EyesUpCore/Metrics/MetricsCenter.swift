import Foundation
import Observation

/// A surface's claim on some metrics. Cancelling it stops that surface's sampling.
@MainActor
public final class MetricsSubscription {
    let id = UUID()
    let ids: Set<MetricID>
    let interval: TimeInterval
    private weak var center: MetricsCenter?

    init(ids: Set<MetricID>, interval: TimeInterval, center: MetricsCenter) {
        self.ids = ids
        self.interval = interval
        self.center = center
    }

    public func cancel() {
        center?.remove(self)
        center = nil
    }

    /// Backstop for a surface that goes away without cancelling: hopping to the main actor through a
    /// Task is safe from a non-isolated deinit (unlike assumeIsolated, which would trap).
    deinit {
        guard let center else { return }
        let id = id
        Task { @MainActor in center.remove(subscriptionID: id) }
    }
}

/// Samples what's subscribed — each metric at its own cadence — and nothing at all when nobody is
/// looking (spec §3.1, §6.1).
///
/// Cadence is per metric, not per tick: the process list is by far the most expensive thing here,
/// and a menu-bar readout asking for CPU every two seconds must not drag it along at that rate.
@MainActor
@Observable
public final class MetricsCenter {
    /// Five minutes of 1 s samples (spec §3.4).
    public static let historyLength = 300

    public private(set) var snapshot = MetricsSnapshot()

    public var isSampling: Bool { !subscriptions.isEmpty }

    @ObservationIgnored private let probes: any MetricsProbing
    @ObservationIgnored private let executor: any MetricsExecuting
    @ObservationIgnored private let clock: any WallClock
    @ObservationIgnored private let scheduler: any TimerScheduling
    @ObservationIgnored private var subscriptions: [UUID: (ids: Set<MetricID>, interval: TimeInterval)] = [:]
    @ObservationIgnored private var histories: [MetricID: [Double]] = [:]
    @ObservationIgnored private var task: (any ScheduledTask)?
    /// When each metric may next be sampled.
    @ObservationIgnored private var nextDue: [MetricID: Date] = [:]

    public init(
        probes: any MetricsProbing,
        executor: any MetricsExecuting = BackgroundExecutor(),
        clock: any WallClock = SystemClock(),
        scheduler: any TimerScheduling
    ) {
        self.probes = probes
        self.executor = executor
        self.clock = clock
        self.scheduler = scheduler
    }

    public func subscribe(_ ids: Set<MetricID>, interval: TimeInterval) -> MetricsSubscription {
        let subscription = MetricsSubscription(ids: ids, interval: max(0.5, interval), center: self)
        subscriptions[subscription.id] = (ids, subscription.interval)
        // A metric nobody was watching is sampled at once, so a surface opens with numbers on it.
        // One already being sampled keeps its place in the cycle, pulled in if this subscriber
        // asked for it faster.
        let soon = clock.now.addingTimeInterval(subscription.interval)
        for id in ids {
            if let due = nextDue[id] { nextDue[id] = min(due, soon) }
        }
        sampleNow()
        return subscription
    }

    /// The recent history of a metric's headline number, oldest first.
    public func history(_ id: MetricID) -> [Double] {
        histories[id] ?? []
    }

    /// After a wake or a clock change: drop stale baselines and take a fresh sample.
    public func refresh() {
        histories.removeAll()
        // A wake invalidates every reading, whatever its cadence.
        nextDue.removeAll()
        // resetBaselines takes the probe lock, so it belongs on the sampling queue: a wake must
        // never stall the main actor for the length of a sample.
        let probes = probes
        executor.run({
            probes.resetBaselines()
            return MetricsSnapshot()
        }, completion: { _ in })
        sampleNow()
    }

    func remove(_ subscription: MetricsSubscription) {
        remove(subscriptionID: subscription.id)
    }

    func remove(subscriptionID: UUID) {
        subscriptions[subscriptionID] = nil
        let wanted = requestedIDs
        nextDue = nextDue.filter { wanted.contains($0.key) }
        if subscriptions.isEmpty {
            task?.cancel()
            task = nil
        } else {
            rearm()
        }
    }

    private var requestedIDs: Set<MetricID> {
        subscriptions.values.reduce(into: Set<MetricID>()) { $0.formUnion($1.ids) }
    }

    private var interval: TimeInterval {
        subscriptions.values.map(\.interval).min() ?? 1
    }

    /// The fastest rate anyone asked this metric for.
    private func interval(for id: MetricID) -> TimeInterval {
        subscriptions.values.filter { $0.ids.contains(id) }.map(\.interval).min() ?? interval
    }

    /// Timers fire a little late, so a metric a hair short of due is counted as due rather than
    /// waiting a whole extra cycle.
    private static let dueSlack: TimeInterval = 0.05

    private func sampleNow() {
        task?.cancel()
        task = nil
        guard !subscriptions.isEmpty else { return }

        let now = clock.now
        let ids = requestedIDs.filter { id in
            guard let due = nextDue[id] else { return true }
            return due <= now.addingTimeInterval(Self.dueSlack)
        }
        guard !ids.isEmpty else {
            rearm()
            return
        }
        for id in ids { nextDue[id] = now.addingTimeInterval(interval(for: id)) }

        let probes = probes
        executor.run({ probes.sample(ids) }) { [weak self] fresh in
            self?.apply(fresh, requested: ids)
        }
        rearm()
    }

    private func rearm() {
        task?.cancel()
        guard !subscriptions.isEmpty else {
            task = nil
            return
        }
        // Wake when the soonest metric is next due, not on a fixed tick.
        let wanted = requestedIDs
        let soonest = wanted.compactMap { nextDue[$0] }.min() ?? clock.now.addingTimeInterval(interval)
        let at = max(soonest, clock.now.addingTimeInterval(min(interval, 0.5)))
        task = scheduler.schedule(at: at) { [weak self] in self?.sampleNow() }
    }

    private func apply(_ fresh: MetricsSnapshot, requested: Set<MetricID>) {
        // Metrics we asked for but didn't get are unavailable now, so they blank instead of going stale.
        var merged = snapshot
        for id in requested { merged.clear(id) }
        snapshot = merged.merging(fresh)
        record(fresh)
    }

    private func record(_ fresh: MetricsSnapshot) {
        var values: [MetricID: Double] = [:]
        if let cpu = fresh.cpu { values[.cpu] = cpu.total }
        if let memory = fresh.memory, memory.totalBytes > 0 {
            values[.memory] = Double(memory.usedBytes) / Double(memory.totalBytes) * 100
        }
        if let power = fresh.power { values[.power] = power.watts }
        if let gpu = fresh.gpu { values[.gpu] = gpu.utilization }
        if let temperature = fresh.temperature { values[.temperature] = temperature.celsius }
        if let network = fresh.network { values[.network] = (network.inBytesPerSecond ?? 0) + (network.outBytesPerSecond ?? 0) }
        if let storage = fresh.storage {
            values[.storage] = (storage.readBytesPerSecond ?? 0) + (storage.writeBytesPerSecond ?? 0)
        }
        for (id, value) in values {
            var series = histories[id] ?? []
            series.append(value)
            if series.count > Self.historyLength { series.removeFirst(series.count - Self.historyLength) }
            histories[id] = series
        }
    }
}

extension MetricsSnapshot {
    /// Used by the center to blank a metric that was requested but came back empty.
    mutating func clear(_ id: MetricID) {
        switch id {
        case .cpu: cpu = nil
        case .memory: memory = nil
        case .system: system = nil
        case .storage: storage = nil
        case .network: network = nil
        case .processes: processes = nil
        case .power: power = nil
        case .fans: fans = nil
        case .temperature: temperature = nil
        case .gpu: gpu = nil
        case .otherAssertions: otherAssertions = nil
        }
    }
}
