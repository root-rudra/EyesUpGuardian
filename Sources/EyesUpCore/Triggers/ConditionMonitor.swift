import Foundation

/// Watches one trigger's condition and reports its answer: once at `start`, then on every change.
@MainActor
public protocol ConditionMonitor: AnyObject {
    func start(_ report: @escaping @MainActor (Bool) -> Void)
    func stop()
    /// Re-check after a wake, clock change or timezone change.
    func reevaluate()
}

@MainActor
public protocol ConditionMonitorFactory: AnyObject {
    func makeMonitor(for condition: TriggerCondition) -> any ConditionMonitor
}
