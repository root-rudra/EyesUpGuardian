import Foundation

/// What the one-switch toggle (the ⌃⌥⌘E shortcut, the menu's switch) should do next.
///
/// It is not simply "stop everything": `stopAll` spares trigger holds on purpose, so when a trigger
/// is the only thing holding the Mac awake, stopping would do nothing at all and say nothing either.
public enum KeepAwakeToggleAction: Equatable, Sendable {
    case stopManualSessions
    case pauseTriggers
    case resumeTriggers
    case startIndefinite
}

public enum KeepAwakeToggle {
    public static func next(holds: [Hold], triggersPaused: Bool) -> KeepAwakeToggleAction {
        if holds.contains(where: { !$0.source.isTrigger }) { return .stopManualSessions }
        if holds.contains(where: { $0.source.isTrigger }) { return .pauseTriggers }
        if triggersPaused { return .resumeTriggers }
        return .startIndefinite
    }
}
