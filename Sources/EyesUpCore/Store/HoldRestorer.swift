import Foundation

/// Spec §4.4: which saved holds survive a relaunch.
/// A saved file is untrusted input (spec §9.5), so holds must also pass the limits that creating a hold enforces.
public enum HoldRestorer {
    /// Longest grace period a saved hold may carry.
    public static let maxGrace: TimeInterval = 24 * 3600
    /// Longest label a saved hold may carry.
    public static let maxLabelLength = 200
    /// A saved hold may be stamped slightly in the future (clock changes), but not meaningfully so.
    public static let maxClockSkew: TimeInterval = 300
    public static let knownPolicy: SleepPolicy = [.system, .display, .disk, .systemOnAC]

    /// The hold with unknown policy bits removed, or nil if it breaks a creation limit.
    public static func sanitized(
        _ saved: Hold,
        now: Date,
        maxDuration: TimeInterval = AwakeController.maxManualDuration
    ) -> Hold? {
        var hold = saved
        hold.policy = hold.policy.intersection(knownPolicy)
        guard !hold.policy.isEmpty, hold.label.count <= maxLabelLength else { return nil }
        // A createdAt in the future would push `createdAt + safetyCap` out of reach, so the cap would never bite.
        guard hold.createdAt.timeIntervalSince(now) <= maxClockSkew else { return nil }
        if let grace = hold.grace, !(0...maxGrace).contains(grace) { return nil }
        if let deadline = hold.effectiveDeadline, deadline.timeIntervalSince(now) > maxDuration + maxGrace { return nil }
        return hold
    }

    public static func restorable(_ holds: [Hold], now: Date, inspector: any ProcessInspecting) -> [Hold] {
        holds.compactMap { sanitized($0, now: now) }.filter { hold in
            guard !hold.source.isTrigger else { return false }
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
