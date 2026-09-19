import Foundation

/// A process pinned by PID *and* start time, so a recycled PID is never mistaken for the original.
public struct ProcessIdentity: Codable, Hashable, Sendable {
    public let pid: Int32
    /// Start time in microseconds since 1970.
    public let startTime: UInt64

    public init(pid: Int32, startTime: UInt64) {
        self.pid = pid
        self.startTime = startTime
    }
}

public enum HoldSource: Codable, Hashable, Sendable {
    case manual
    case trigger(UUID)
    case automation

    public var isTrigger: Bool {
        if case .trigger = self { return true }
        return false
    }
}

public enum HoldEnd: Codable, Hashable, Sendable {
    case indefinite
    case deadline(Date)
    case processExit(ProcessIdentity)
    case triggerControlled
}

/// One reason to keep the Mac awake.
public struct Hold: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var source: HoldSource
    public var label: String
    public var policy: SleepPolicy
    public var end: HoldEnd
    /// Extra time to stay awake after the end condition is met.
    public var grace: TimeInterval?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        source: HoldSource = .manual,
        label: String,
        policy: SleepPolicy,
        end: HoldEnd,
        grace: TimeInterval? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.source = source
        self.label = label
        self.policy = policy
        self.end = end
        self.grace = grace
        self.createdAt = createdAt
    }

    /// The moment this hold expires, including grace; nil if it has no deadline.
    public var effectiveDeadline: Date? {
        guard case .deadline(let date) = end else { return nil }
        return date.addingTimeInterval(grace ?? 0)
    }

    /// A manual timer or indefinite session. Starting a new one replaces the old one.
    public var isManualSession: Bool {
        guard source == .manual else { return false }
        switch end {
        case .indefinite, .deadline: return true
        case .processExit, .triggerControlled: return false
        }
    }

    /// When this hold ends, counting its grace and any safety cap (spec §4.5).
    public func expiry(safetyCap: TimeInterval?) -> Date? {
        let capped = safetyCap.map { createdAt.addingTimeInterval($0) }
        switch (effectiveDeadline, capped) {
        case (let deadline?, let cap?): return min(deadline, cap)
        case (let deadline?, nil): return deadline
        case (nil, let cap?): return cap
        case (nil, nil): return nil
        }
    }

    /// When the Mac may sleep again, or nil if there are no holds or any hold has no end.
    public static func awakeUntil(_ holds: [Hold], safetyCap: TimeInterval? = nil) -> Date? {
        guard !holds.isEmpty else { return nil }
        var latest = Date.distantPast
        for hold in holds {
            guard let end = hold.expiry(safetyCap: safetyCap) else { return nil }
            latest = max(latest, end)
        }
        return latest
    }
}
