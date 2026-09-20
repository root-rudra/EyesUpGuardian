import Foundation

/// Short, honest stat text. Anything missing or nonsensical reads as "—" rather than a fake number.
public enum StatFormatting {
    public static let unavailable = "—"

    public static func bytes(_ value: UInt64?) -> String {
        guard let value else { return unavailable }
        let units: [(threshold: Double, suffix: String)] = [
            (1_000_000_000_000, "TB"), (1_000_000_000, "GB"), (1_000_000, "MB"), (1000, "KB"),
        ]
        let amount = Double(value)
        for unit in units where amount >= unit.threshold {
            return String(format: "%.1f %@", amount / unit.threshold, unit.suffix)
        }
        return "\(value) B"
    }

    public static func rate(_ bytesPerSecond: Double?) -> String {
        guard let value = bytesPerSecond, value.isFinite, value >= 0 else { return unavailable }
        guard value >= 1000 else { return "\(Int(value)) B/s" }
        // Double(UInt64.max) rounds UP past UInt64.max, so it is not a usable clamp; 2^53 is the
        // largest integer a Double represents exactly.
        return bytes(UInt64(min(value, 9_007_199_254_740_992))) + "/s"
    }

    public static func percent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return unavailable }
        return "\(Int(min(max(value, 0), 100).rounded()))%"
    }

    public static func watts(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return unavailable }
        return String(format: "%.1f W", value)
    }

    /// Beyond these a reading isn't a temperature or a fan speed, and `Int(3.4e38)` traps rather
    /// than formats.
    private static let temperatureRange = -100.0...200.0
    private static let rpmRange = 0.0...30_000.0

    public static func celsius(_ value: Double?) -> String {
        guard let value, value.isFinite, temperatureRange.contains(value) else { return unavailable }
        return "\(Int(value.rounded()))°C"
    }

    public static func rpm(_ value: Double?) -> String {
        guard let value, value.isFinite, rpmRange.contains(value) else { return unavailable }
        return "\(Int(value.rounded())) rpm"
    }

    /// "6d 4h", "3h 10m", "42m".
    public static func uptime(since bootTime: Date?, now: Date = Date()) -> String {
        guard let bootTime, now > bootTime else { return unavailable }
        let total = Int(now.timeIntervalSince(bootTime))
        let days = total / 86_400
        let hours = (total % 86_400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(max(minutes, 1))m"
    }

    public static func idle(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return unavailable }
        guard seconds >= 60 else { return "just now" }
        return TimeFormatting.duration(seconds)
    }
}

/// Text that came from outside the app — a saved file, another process's name — before it is shown
/// anywhere a person might act on it.
public enum SafeText {
    /// Drops control and formatting characters (bidi overrides, zero-width joiners, soft hyphens) and
    /// turns exotic whitespace into plain spaces, so a name cannot forge a line, reverse how it reads,
    /// or hide characters in the middle of it.
    public static func display(_ raw: String, limit: Int? = nil) -> String {
        let cleaned = String(String.UnicodeScalarView(raw.unicodeScalars.compactMap { scalar in
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator, .privateUse, .unassigned, .surrogate:
                return nil
            default:
                return scalar.properties.isWhitespace && !scalar.isASCII ? " " : scalar
            }
        }))
        let collapsed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let limit else { return collapsed }
        return String(collapsed.prefix(limit))
    }
}
