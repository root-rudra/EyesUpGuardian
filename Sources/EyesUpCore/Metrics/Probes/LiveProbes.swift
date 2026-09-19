import Foundation

/// Every real probe behind one `MetricsProbing`. Sampling happens off the main thread, so the
/// mutable probe state is guarded by a lock rather than an actor.
public final class LiveProbes: MetricsProbing, @unchecked Sendable {
    private let lock = NSLock()
    private let cpu = CPUProbe()
    private let memory = MemoryProbe()
    private let system = SystemProbe()
    private let storage: StorageProbe
    private let network: NetworkProbe
    private let processes: ProcessProbe
    private let assertions = AssertionProbe()
    private let gpu = GPUProbe()
    private let smc: SMCProbe?

    public init(counters: any SystemCounters = LiveSystemCounters(), clock: any WallClock = SystemClock()) {
        storage = StorageProbe(counters: counters, clock: clock)
        network = NetworkProbe(counters: counters, clock: clock)
        processes = ProcessProbe(clock: clock)
        smc = SMC().map { SMCProbe(smc: $0) }
    }

    public func sample(_ ids: Set<MetricID>) -> MetricsSnapshot {
        lock.lock()
        defer { lock.unlock() }

        var snapshot = MetricsSnapshot()
        if ids.contains(.cpu) { snapshot.cpu = cpu.sample() }
        if ids.contains(.memory) { snapshot.memory = memory.sample() }
        if ids.contains(.system) { snapshot.system = system.sample() }
        if ids.contains(.storage) { snapshot.storage = storage.sample() }
        if ids.contains(.network) { snapshot.network = network.sample() }
        if ids.contains(.processes) { snapshot.processes = processes.sample() }
        if ids.contains(.gpu) { snapshot.gpu = gpu.sample() }
        if ids.contains(.otherAssertions) { snapshot.otherAssertions = assertions.sample() }
        if ids.contains(.power) { snapshot.power = smc?.power() }
        if ids.contains(.fans) { snapshot.fans = smc?.fans() }
        if ids.contains(.temperature) { snapshot.temperature = smc?.temperature() }
        return snapshot
    }

    public func resetBaselines() {
        lock.lock()
        defer { lock.unlock() }
        storage.resetBaseline()
        network.resetBaseline()
    }
}
