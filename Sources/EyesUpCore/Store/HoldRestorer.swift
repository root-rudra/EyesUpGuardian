import Foundation

/// Spec §4.4: which saved holds survive a relaunch.
public enum HoldRestorer {
    public static func restorable(_ holds: [Hold], now: Date, inspector: any ProcessInspecting) -> [Hold] {
        holds.filter { hold in
            switch hold.end {
            case .indefinite:
                return true
            case .deadline:
                return (hold.effectiveDeadline ?? now) > now
            case .processExit(let identity):
                return inspector.identity(of: identity.pid) == identity
            case .triggerControlled:
                return false
            }
        }
    }
}
