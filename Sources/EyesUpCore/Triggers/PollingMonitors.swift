import Foundation

/// True while any named command-line process is running. Polls only while its trigger is enabled.
@MainActor
public final class ProcessRunningMonitor: ConditionMonitor {
    public static let interval: TimeInterval = 10

    private let names: Set<String>
    private let lister: any ProcessLister
    private let clock: any WallClock
    private let scheduler: any TimerScheduling
    private var report: (@MainActor (Bool) -> Void)?
    private var task: (any ScheduledTask)?

    public init(names: [String], lister: any ProcessLister, clock: any WallClock, scheduler: any TimerScheduling) {
        self.names = Set(names.map { $0.lowercased() })
        self.lister = lister
        self.clock = clock
        self.scheduler = scheduler
    }

    public func start(_ report: @escaping @MainActor (Bool) -> Void) {
        self.report = report
        poll()
    }

    public func stop() {
        task?.cancel()
        task = nil
        report = nil
    }

    public func reevaluate() { poll() }

    private func poll() {
        task?.cancel()
        let running = Set(lister.runningProcessNames().map { $0.lowercased() })
        report?(!running.isDisjoint(with: names))
        task = scheduler.schedule(at: clock.now.addingTimeInterval(Self.interval)) { [weak self] in self?.poll() }
    }
}

/// True while the Mac is busy: CPU percent, network bytes/second or disk writes/second,
/// smoothed by an ActivityGate so brief spikes don't flap the hold.
@MainActor
public final class ActivityMonitor: ConditionMonitor {
    public enum Kind: Sendable { case cpu, network, disk }
    public static let interval: TimeInterval = 15

    private let kind: Kind
    private let counters: any SystemCounters
    private let clock: any WallClock
    private let scheduler: any TimerScheduling
    private var gate: ActivityGate
    private var rate = RateMeter()
    private var cpu = CPUMeter()
    private var report: (@MainActor (Bool) -> Void)?
    private var task: (any ScheduledTask)?

    public init(
        kind: Kind,
        threshold: ActivityThreshold,
        counters: any SystemCounters,
        clock: any WallClock,
        scheduler: any TimerScheduling
    ) {
        self.kind = kind
        self.counters = counters
        self.clock = clock
        self.scheduler = scheduler
        gate = ActivityGate(threshold: threshold)
    }

    public func start(_ report: @escaping @MainActor (Bool) -> Void) {
        self.report = report
        report(gate.isOn) // the first sample only sets a baseline
        poll()
    }

    public func stop() {
        task?.cancel()
        task = nil
        report = nil
    }

    /// Counters jump while the Mac sleeps, so start a fresh baseline instead of reading a huge rate.
    public func reevaluate() {
        rate = RateMeter()
        cpu = CPUMeter()
        poll()
    }

    private func poll() {
        task?.cancel()
        if let value = currentValue() {
            report?(gate.update(value: value, at: clock.now))
        }
        task = scheduler.schedule(at: clock.now.addingTimeInterval(Self.interval)) { [weak self] in self?.poll() }
    }

    private func currentValue() -> Double? {
        switch kind {
        case .cpu:
            guard let ticks = counters.cpuTicks() else { return nil }
            return cpu.percent(busy: ticks.busy, total: ticks.total)
        case .network:
            guard let bytes = counters.networkBytes() else { return nil }
            return rate.rate(for: bytes, at: clock.now)
        case .disk:
            guard let bytes = counters.diskBytesWritten() else { return nil }
            return rate.rate(for: bytes, at: clock.now)
        }
    }
}
