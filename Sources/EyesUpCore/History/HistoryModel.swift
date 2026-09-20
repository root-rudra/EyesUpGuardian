import Foundation

/// One finished keep-awake session.
public struct Session: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var startedAt: Date
    public var endedAt: Date
    /// The labels that were holding at the moment it ended, e.g. ["Timer 2h", "Claude running"].
    public var reasons: [String]
    /// "manual", "trigger" or "automation".
    public var source: String

    public init(id: UUID = UUID(), startedAt: Date, endedAt: Date, reasons: [String], source: String) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.reasons = reasons
        self.source = source
    }

    public var duration: TimeInterval { max(0, endedAt.timeIntervalSince(startedAt)) }
}

/// Energy used on one calendar day, and how long the Mac was held awake that day.
public struct EnergyDay: Codable, Hashable, Sendable {
    public var day: Date
    public var kilowattHours: Double
    public var awakeSeconds: TimeInterval

    public init(day: Date, kilowattHours: Double, awakeSeconds: TimeInterval) {
        self.day = day
        self.kilowattHours = kilowattHours
        self.awakeSeconds = awakeSeconds
    }
}

public struct SleepWakeEvent: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case slept, woke
    }

    public var at: Date
    public var kind: Kind

    public init(at: Date, kind: Kind) {
        self.at = at
        self.kind = kind
    }
}

/// Everything the app remembers about the past (spec §8). Capped by count and pruned by age.
public struct HistorySnapshot: Codable, Equatable, Sendable {
    public static let retentionDays = 90.0
    public static let maxSessions = 2000
    public static let maxEnergyDays = 400
    public static let maxEvents = 2000
    /// Longest a single session may claim to have run.
    public static let maxSessionDuration: TimeInterval = 30 * 86_400
    public static let maxReasonLength = 200
    /// A day's energy above this is not believable for a desktop Mac and is dropped.
    public static let maxDailyKilowattHours = 100.0

    public var sessions: [Session] = []
    public var energy: [EnergyDay] = []
    public var sleepWake: [SleepWakeEvent] = []

    public init() {}

    public func awakeSeconds(since: Date, now: Date = Date()) -> TimeInterval {
        sessions.filter { $0.endedAt >= since && $0.startedAt <= now }.reduce(0) { $0 + $1.duration }
    }

    public func kilowattHours(since: Date) -> Double {
        energy.filter { $0.day >= since }.reduce(0) { $0 + $1.kilowattHours }
    }

    /// Caps first, then validates: a tampered file costs no more work than a normal one.
    public func sanitized(now: Date = Date()) -> HistorySnapshot {
        let oldest = now.addingTimeInterval(-Self.retentionDays * 86_400)
        var clean = HistorySnapshot()

        clean.sessions = sessions.suffix(Self.maxSessions).compactMap { session in
            guard session.endedAt > session.startedAt,
                  session.startedAt <= now,
                  session.endedAt >= oldest,
                  session.duration <= Self.maxSessionDuration else { return nil }
            var kept = session
            kept.reasons = session.reasons.prefix(8).map { SafeText.display($0, limit: Self.maxReasonLength) }
            kept.source = SafeText.display(session.source, limit: 20)
            return kept
        }

        clean.energy = energy.suffix(Self.maxEnergyDays).filter { day in
            day.kilowattHours.isFinite && day.kilowattHours >= 0 && day.kilowattHours <= Self.maxDailyKilowattHours
                && day.awakeSeconds.isFinite && day.awakeSeconds >= 0
                && day.day >= oldest && day.day <= now.addingTimeInterval(86_400)
        }

        clean.sleepWake = sleepWake.suffix(Self.maxEvents).filter { $0.at >= oldest && $0.at <= now }
        return clean
    }
}
