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

    // No deinit: `deinit` is not main-actor isolated, and hopping there from one would either trap or
    // race. Every surface cancels explicitly in `onDisappear`, and Task 8's tests pin that.
}

/// Samples the union of what's subscribed, at the fastest interval asked for, and nothing at all
/// when nobody is looking (spec §3.1, §6.1).
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
        sampleNow()
        return subscription
    }

    /// The recent history of a metric's headline number, oldest first.
    public func history(_ id: MetricID) -> [Double] {
        histories[id] ?? []
    }

    /// After a wake or a clock change: drop stale baselines and take a fresh sample.
    public func refresh() {
        probes.resetBaselines()
        histories.removeAll()
        sampleNow()
    }

    func remove(_ subscription: MetricsSubscription) {
        remove(subscriptionID: subscription.id)
    }

    func remove(subscriptionID: UUID) {
        subscriptions[subscriptionID] = nil
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

    private func sampleNow() {
        task?.cancel()
        task = nil
        let ids = requestedIDs
        guard !ids.isEmpty else { return }

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
        task = scheduler.schedule(at: clock.now.addingTimeInterval(interval)) { [weak self] in self?.sampleNow() }
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
