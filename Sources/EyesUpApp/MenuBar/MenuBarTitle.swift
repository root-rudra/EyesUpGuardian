import EyesUpCore
import Foundation

/// The text beside the menu-bar ring.
///
/// Kept apart from the status item so the rules can be tested: a readout that promises the time
/// left and then shows nothing is the kind of thing only a person notices, and only by chance.
enum MenuBarTitle {
    /// - Parameters:
    ///   - deadline: the soonest session end, or nil when nothing the user started has an end.
    ///   - endless: something is holding with no end (a trigger, or an uncapped indefinite session).
    static func text(
        readout: MenuBarReadout,
        isAwake: Bool,
        deadline: Date?,
        endless: Bool,
        now: Date,
        stat: String
    ) -> String {
        var parts: [String] = []
        if readout != .iconOnly, isAwake {
            switch (deadline, endless) {
            case (let end?, false):
                parts.append(TimeFormatting.menuBar(remaining: end.timeIntervalSince(now)))
            case (let end?, true):
                // Honest about both: this session ends then, but the Mac stays awake after it.
                parts.append(TimeFormatting.menuBar(remaining: end.timeIntervalSince(now)) + " ∞")
            case (nil, true):
                parts.append("∞")
            case (nil, false):
                break
            }
        }
        if !stat.isEmpty { parts.append(stat) }
        guard !parts.isEmpty else { return "" }
        return " " + parts.joined(separator: " · ")
    }
}
