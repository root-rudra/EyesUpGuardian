import Foundation

public struct TriggerSuggestion: Identifiable, Hashable, Sendable {
    public var id: String { bundleID }
    public let bundleID: String
    public let displayName: String
}

/// One-click "Keep awake while X runs?" offers for apps the user already has open (spec §5).
public enum TriggerSuggestions {
    public static let knownApps: [(bundleID: String, name: String)] = [
        ("com.anthropic.claudefordesktop", "Claude"),
        ("com.apple.Terminal", "Terminal"),
        ("com.googlecode.iterm2", "iTerm"),
        ("com.apple.dt.Xcode", "Xcode"),
        ("com.microsoft.VSCode", "Visual Studio Code"),
        ("com.docker.docker", "Docker"),
    ]

    public static func suggestions(running: Set<String>, existing: [Trigger]) -> [TriggerSuggestion] {
        var covered: Set<String> = []
        for trigger in existing {
            if case .appRunning(let ids) = trigger.condition { covered.formUnion(ids) }
        }
        return knownApps
            .filter { running.contains($0.bundleID) && !covered.contains($0.bundleID) }
            .map { TriggerSuggestion(bundleID: $0.bundleID, displayName: $0.name) }
    }
}
