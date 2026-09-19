import Foundation

/// A day-of-week plus time-of-day window. Minutes are minutes since local midnight.
public struct Schedule: Codable, Hashable, Sendable {
    /// Calendar weekdays (1 = Sunday … 7 = Saturday) on which the window *starts*.
    public var weekdays: Set<Int>
    public var startMinute: Int
    public var endMinute: Int

    public init(weekdays: Set<Int>, startMinute: Int, endMinute: Int) {
        self.weekdays = weekdays
        self.startMinute = startMinute
        self.endMinute = endMinute
    }
}

/// A threshold plus the "busy for" and "quiet for" times that stop it flickering.
public struct ActivityThreshold: Codable, Hashable, Sendable {
    /// CPU uses percent (1…100); network and disk use bytes per second.
    public var value: Double
    public var sustain: TimeInterval
    public var release: TimeInterval

    public init(value: Double, sustain: TimeInterval = 120, release: TimeInterval = 300) {
        self.value = value
        self.sustain = sustain
        self.release = release
    }
}

/// Identifies a display across unplugs, using CoreGraphics' vendor/model/serial numbers.
public struct DisplayMatch: Codable, Hashable, Sendable {
    public var vendor: UInt32
    public var model: UInt32
    public var serial: UInt32
    public var name: String

    public init(vendor: UInt32, model: UInt32, serial: UInt32, name: String) {
        self.vendor = vendor
        self.model = model
        self.serial = serial
        self.name = name
    }

    public func matches(_ other: DisplayMatch) -> Bool {
        vendor == other.vendor && model == other.model && serial == other.serial
    }
}

public enum TriggerCondition: Codable, Hashable, Sendable {
    case appRunning(bundleIDs: [String])
    case processRunning(names: [String])
    case schedule(Schedule)
    case cpuBusy(ActivityThreshold)
    case networkBusy(ActivityThreshold)
    case diskBusy(ActivityThreshold)
    case displayConnected(DisplayMatch)
    case onACPower
}

/// A saved rule: while its condition holds, the Mac stays awake.
public struct Trigger: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var condition: TriggerCondition
    public var policy: SleepPolicy
    /// Stay awake this long after the condition ends.
    public var grace: TimeInterval
    public var notifyOnChange: Bool
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        condition: TriggerCondition,
        policy: SleepPolicy = .system,
        grace: TimeInterval = 0,
        notifyOnChange: Bool = false,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.condition = condition
        self.policy = policy
        self.grace = grace
        self.notifyOnChange = notifyOnChange
        self.isEnabled = isEnabled
    }

    public var summary: String {
        switch condition {
        case .appRunning(let ids): "While \(Self.list(ids)) is open"
        case .processRunning(let names): "While \(Self.list(names)) is running"
        case .schedule(let schedule): "On \(schedule.weekdaySummary) from \(Schedule.time(schedule.startMinute)) to \(Schedule.time(schedule.endMinute))"
        case .cpuBusy(let threshold): "While CPU is above \(Int(threshold.value))% for \(TimeFormatting.duration(threshold.sustain))"
        case .networkBusy(let threshold): "While network traffic is above \(Self.rate(threshold.value)) for \(TimeFormatting.duration(threshold.sustain))"
        case .diskBusy(let threshold): "While disk writes are above \(Self.rate(threshold.value)) for \(TimeFormatting.duration(threshold.sustain))"
        case .displayConnected(let display): "While \(display.name) is connected"
        case .onACPower: "While on AC power"
        }
    }

    private static func list(_ values: [String]) -> String {
        guard values.count > 1 else { return values.first ?? "" }
        return values.dropLast().joined(separator: ", ") + " or " + (values.last ?? "")
    }

    private static func rate(_ bytesPerSecond: Double) -> String {
        let megabytes = bytesPerSecond / 1_000_000
        return megabytes >= 1 ? String(format: "%.0f MB/s", megabytes) : String(format: "%.0f KB/s", bytesPerSecond / 1000)
    }
}

extension Schedule {
    public static func time(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    public var weekdaySummary: String {
        let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let selected = weekdays.sorted().compactMap { (1...7).contains($0) ? names[$0 - 1] : nil }
        if Set(weekdays) == Set(2...6) { return "weekdays" }
        if Set(weekdays) == Set([1, 7]) { return "weekends" }
        if weekdays.count == 7 { return "every day" }
        return selected.joined(separator: ", ")
    }
}
