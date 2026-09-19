/// Which kinds of sleep a hold prevents. Mirrors caffeinate's -i, -d, -m and -s flags.
public struct SleepPolicy: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// caffeinate -i: keep the Mac awake; the display may sleep.
    public static let system = SleepPolicy(rawValue: 1 << 0)
    /// caffeinate -d: keep the display on.
    public static let display = SleepPolicy(rawValue: 1 << 1)
    /// caffeinate -m: keep disks from idling.
    public static let disk = SleepPolicy(rawValue: 1 << 2)
    /// caffeinate -s: prevent all system sleep (macOS honors this only on AC power).
    public static let systemOnAC = SleepPolicy(rawValue: 1 << 3)
}

/// One IOKit power assertion type.
public enum AssertionKind: String, CaseIterable, Hashable, Sendable {
    case preventDisplaySleep
    case preventIdleSystemSleep
    case preventSystemSleep
    case preventDiskIdle

    /// The assertion type string IOKit expects.
    public var ioKitType: String {
        switch self {
        case .preventDisplaySleep: "PreventUserIdleDisplaySleep"
        case .preventIdleSystemSleep: "PreventUserIdleSystemSleep"
        case .preventSystemSleep: "PreventSystemSleep"
        case .preventDiskIdle: "PreventDiskIdle"
        }
    }

    public static func kinds(for policy: SleepPolicy) -> Set<AssertionKind> {
        var kinds: Set<AssertionKind> = []
        if policy.contains(.system) { kinds.insert(.preventIdleSystemSleep) }
        if policy.contains(.display) { kinds.insert(.preventDisplaySleep) }
        if policy.contains(.disk) { kinds.insert(.preventDiskIdle) }
        if policy.contains(.systemOnAC) { kinds.insert(.preventSystemSleep) }
        return kinds
    }
}
