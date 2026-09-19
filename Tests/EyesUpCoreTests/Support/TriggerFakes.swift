import Foundation
@testable import EyesUpCore

func makeTrigger(
    id: UUID = UUID(),
    name: String = "Test trigger",
    condition: TriggerCondition = .onACPower,
    policy: SleepPolicy = .system,
    grace: TimeInterval = 0,
    notifyOnChange: Bool = false,
    isEnabled: Bool = true
) -> Trigger {
    Trigger(id: id, name: name, condition: condition, policy: policy, grace: grace,
            notifyOnChange: notifyOnChange, isEnabled: isEnabled)
}

@MainActor
final class FakeConditionMonitor: ConditionMonitor {
    let condition: TriggerCondition
    private(set) var isStarted = false
    private(set) var reevaluateCount = 0
    private var report: (@MainActor (Bool) -> Void)?

    init(condition: TriggerCondition) { self.condition = condition }

    func start(_ report: @escaping @MainActor (Bool) -> Void) {
        isStarted = true
        self.report = report
    }

    func stop() {
        isStarted = false
        report = nil
    }

    func reevaluate() { reevaluateCount += 1 }

    /// Test hook: pretend the condition changed.
    func send(_ met: Bool) { report?(met) }
}

@MainActor
final class FakeMonitorFactory: ConditionMonitorFactory {
    private(set) var made: [FakeConditionMonitor] = []

    func makeMonitor(for condition: TriggerCondition) -> any ConditionMonitor {
        let monitor = FakeConditionMonitor(condition: condition)
        made.append(monitor)
        return monitor
    }

    var last: FakeConditionMonitor? { made.last }
}

@MainActor
final class FakeWorkspace: WorkspaceEvents {
    var running: Set<String> = []
    private var handler: (@MainActor () -> Void)?

    func runningBundleIDs() -> Set<String> { running }

    func observeChanges(_ handler: @escaping @MainActor () -> Void) -> any ScheduledTask {
        self.handler = handler
        return FakeTask { [weak self] in self?.handler = nil }
    }

    /// Test hook: pretend an app launched or quit.
    func change(to running: Set<String>) {
        self.running = running
        handler?()
    }
}

@MainActor
final class FakeDisplays: DisplayInventory {
    var connected: [DisplayMatch] = []
    private var handler: (@MainActor () -> Void)?

    func connectedDisplays() -> [DisplayMatch] { connected }

    func observeChanges(_ handler: @escaping @MainActor () -> Void) -> any ScheduledTask {
        self.handler = handler
        return FakeTask { [weak self] in self?.handler = nil }
    }

    func change(to connected: [DisplayMatch]) {
        self.connected = connected
        handler?()
    }
}

@MainActor
final class FakePowerSource: PowerSourceInfo {
    var onAC = true
    private var handler: (@MainActor () -> Void)?

    func isOnACPower() -> Bool { onAC }

    func observeChanges(_ handler: @escaping @MainActor () -> Void) -> any ScheduledTask {
        self.handler = handler
        return FakeTask { [weak self] in self?.handler = nil }
    }

    func change(to onAC: Bool) {
        self.onAC = onAC
        handler?()
    }
}

final class FakeProcessLister: ProcessLister, @unchecked Sendable {
    var names: Set<String> = []
    func runningProcessNames() -> Set<String> { names }
}

final class FakeCounters: SystemCounters, @unchecked Sendable {
    var cpu: (busy: UInt64, total: UInt64)?
    var network: UInt64?
    var disk: UInt64?

    func cpuTicks() -> (busy: UInt64, total: UInt64)? { cpu }
    func networkBytes() -> UInt64? { network }
    func diskBytesWritten() -> UInt64? { disk }
}

@MainActor
final class FakeThermal: ThermalMonitoring {
    var level: ThermalLevel = .nominal
    private var handler: (@MainActor () -> Void)?

    func currentLevel() -> ThermalLevel { level }

    func observeChanges(_ handler: @escaping @MainActor () -> Void) -> any ScheduledTask {
        self.handler = handler
        return FakeTask { [weak self] in self?.handler = nil }
    }

    func change(to level: ThermalLevel) {
        self.level = level
        handler?()
    }
}
