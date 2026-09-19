import Foundation

/// The only things a link may ask for (spec §5.1). It can never quit a process or change settings.
public enum AutomationCommand: Equatable, Sendable {
    case start(duration: ParsedDuration, display: Bool)
    case stop
    case extend(by: TimeInterval)
}

public enum AutomationError: Error, Equatable, Sendable {
    case disabled
    case badScheme
    case unknownCommand
    case badParameter
    case missingParameter

    public var message: String {
        switch self {
        case .disabled: "Automation links are switched off in Settings."
        case .badScheme: "That isn't an eyesup:// link."
        case .unknownCommand: "Use eyesup://start, eyesup://stop or eyesup://extend."
        case .badParameter: "A value in that link isn't allowed."
        case .missingParameter: "That link is missing a duration."
        }
    }
}

public enum AutomationParser {
    public static let scheme = "eyesup"
    /// The longest any link may ask for, whatever the safety cap says.
    public static let maxDuration: TimeInterval = 24 * 3600
    private static let maxQueryItems = 4

    public static func parse(_ url: URL, cap: TimeInterval? = nil) throws -> AutomationCommand {
        guard url.scheme?.lowercased() == scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw AutomationError.badScheme
        }
        // Only eyesup://<command> is accepted: no path, so nothing path-shaped can be smuggled in.
        guard components.path.isEmpty || components.path == "/" else { throw AutomationError.badScheme }
        let command = (components.host ?? "").lowercased()
        let items = components.queryItems ?? []
        guard items.count <= maxQueryItems else { throw AutomationError.badParameter }

        var values: [String: String] = [:]
        for item in items {
            let key = item.name.lowercased()
            guard values[key] == nil else { throw AutomationError.badParameter } // duplicate keys
            values[key] = item.value ?? ""
        }
        let limit = min(maxDuration, cap ?? maxDuration)

        switch command {
        case "start":
            try allow(keys: ["for", "display"], in: values)
            guard let raw = values["for"], !raw.isEmpty else { throw AutomationError.missingParameter }
            return .start(duration: try duration(raw, limit: limit), display: try flag(values["display"]))
        case "stop":
            try allow(keys: [], in: values)
            return .stop
        case "extend":
            try allow(keys: ["by"], in: values)
            guard let raw = values["by"], !raw.isEmpty else { throw AutomationError.missingParameter }
            guard case .finite(let seconds) = try duration(raw, limit: limit) else { throw AutomationError.badParameter }
            return .extend(by: seconds)
        default:
            throw AutomationError.unknownCommand
        }
    }

    private static func allow(keys: Set<String>, in values: [String: String]) throws {
        guard Set(values.keys).isSubset(of: keys) else { throw AutomationError.badParameter }
    }

    private static func duration(_ raw: String, limit: TimeInterval) throws -> ParsedDuration {
        guard raw.count <= 9, !raw.contains(where: \.isWhitespace),
              let parsed = DurationParser.parse(raw) else { throw AutomationError.badParameter }
        if case .finite(let seconds) = parsed, seconds > limit { throw AutomationError.badParameter }
        return parsed
    }

    private static func flag(_ raw: String?) throws -> Bool {
        switch raw?.lowercased() {
        case nil, "": false
        case "1", "true", "yes": true
        case "0", "false", "no": false
        default: throw AutomationError.badParameter
        }
    }
}
