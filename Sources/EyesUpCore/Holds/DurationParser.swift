import Foundation

public enum ParsedDuration: Equatable, Sendable {
    case finite(TimeInterval)
    case infinite
}

/// Parses user-typed durations such as "45m", "2h", "1h30m" or "inf". Everything else is rejected.
public enum DurationParser {
    public static func parse(_ text: String) -> ParsedDuration? {
        let input = text.trimmingCharacters(in: .whitespaces).lowercased()
        if input == "inf" { return .infinite }
        guard !input.isEmpty, input.count <= 9 else { return nil }

        let pattern = /(?:(\d{1,3})h)?(?:(\d{1,4})m)?/.asciiOnlyDigits()
        guard let match = input.wholeMatch(of: pattern), match.1 != nil || match.2 != nil else { return nil }

        let hours = match.1.flatMap { Int($0) } ?? 0
        let minutes = match.2.flatMap { Int($0) } ?? 0
        let total = hours * 3600 + minutes * 60
        guard total > 0 else { return nil }
        return .finite(TimeInterval(total))
    }
}
