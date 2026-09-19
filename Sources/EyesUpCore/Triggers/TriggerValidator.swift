import Foundation

/// Saved triggers are untrusted input (spec §9.5): everything is range-checked before it runs.
public enum TriggerValidator {
    public static let maxNameLength = 80
    public static let maxIdentifierLength = 255
    public static let maxIdentifiers = 32
    public static let maxGrace: TimeInterval = 24 * 3600
    public static let maxSustain: TimeInterval = 24 * 3600
    /// Below this, a network or disk threshold would fire on background noise.
    public static let minByteRate: Double = 1024

    /// The trigger with text trimmed and unknown policy bits removed, or nil if it can't be made valid.
    public static func sanitized(_ trigger: Trigger) -> Trigger? {
        var clean = trigger
        clean.name = String(clean.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxNameLength))
        clean.policy = clean.policy.intersection(HoldRestorer.knownPolicy)
        guard !clean.name.isEmpty, !clean.policy.isEmpty, clean.grace.isFinite, (0...maxGrace).contains(clean.grace) else { return nil }

        switch clean.condition {
        case .appRunning(let ids):
            guard let cleaned = identifiers(ids) else { return nil }
            clean.condition = .appRunning(bundleIDs: cleaned)
        case .processRunning(let names):
            guard let cleaned = identifiers(names) else { return nil }
            clean.condition = .processRunning(names: cleaned)
        case .schedule(let schedule):
            guard !schedule.weekdays.isEmpty, schedule.weekdays.allSatisfy({ (1...7).contains($0) }),
                  (0..<1440).contains(schedule.startMinute), (0..<1440).contains(schedule.endMinute),
                  schedule.startMinute != schedule.endMinute else { return nil }
        case .cpuBusy(let threshold):
            guard threshold.value >= 1, threshold.value <= 100, timings(threshold) else { return nil }
        case .networkBusy(let threshold), .diskBusy(let threshold):
            guard threshold.value.isFinite, threshold.value >= minByteRate, timings(threshold) else { return nil }
        case .displayConnected(let display):
            guard display.vendor != 0 || display.model != 0 || display.serial != 0 else { return nil }
        case .onACPower:
            break
        }
        return clean
    }

    private static func timings(_ threshold: ActivityThreshold) -> Bool {
        threshold.sustain.isFinite && threshold.release.isFinite
            && (0...maxSustain).contains(threshold.sustain) && (0...maxSustain).contains(threshold.release)
    }

    /// Trimmed, de-duplicated, length-limited identifiers; nil when nothing usable is left.
    private static func identifiers(_ values: [String]) -> [String]? {
        var unique: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.count <= maxIdentifierLength,
                  !trimmed.contains(where: \.isNewline), !unique.contains(trimmed) else { continue }
            unique.append(trimmed)
        }
        unique = Array(unique.prefix(maxIdentifiers))
        return unique.isEmpty ? nil : unique
    }
}
