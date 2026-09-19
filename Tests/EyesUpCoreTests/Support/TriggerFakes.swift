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
