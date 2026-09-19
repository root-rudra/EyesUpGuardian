import Foundation

public enum TimeFormatting {
    /// Hold labels: "2h", "1h 30m", "15m", "<1m".
    public static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        guard minutes >= 1 else { return "<1m" }
        let hours = minutes / 60
        let rest = minutes % 60
        if hours > 0 && rest > 0 { return "\(hours)h \(rest)m" }
        if hours > 0 { return "\(hours)h" }
        return "\(rest)m"
    }

    /// Menu-bar readout: "1:42" from one hour up, "42m" below, rounded up to the next minute.
    public static func menuBar(remaining seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "0m" }
        let minutes = Int((seconds / 60).rounded(.up))
        if minutes >= 60 { return String(format: "%d:%02d", minutes / 60, minutes % 60) }
        return "\(minutes)m"
    }

    /// Live countdown: "1:42:10" or "42:10".
    public static func countdown(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// Share of the session still remaining, clamped to 0...1. Drives the draining ring.
    public static func remainingFraction(now: Date, start: Date, end: Date) -> Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        return min(1, max(0, end.timeIntervalSince(now) / total))
    }
}
