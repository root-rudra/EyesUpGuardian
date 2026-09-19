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
