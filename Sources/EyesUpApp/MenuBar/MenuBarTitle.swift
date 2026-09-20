import EyesUpCore
import Foundation

/// The text beside the menu-bar ring.
///
/// Kept apart from the status item so the rules can be tested: a readout that promises the time
/// left and then shows nothing is the kind of thing only a person notices, and only by chance.
enum MenuBarTitle {
    /// A figure space: exactly as wide as a digit in this font, and invisible.
    ///
    /// Without it the item's width changes as digits come and go — "9:59" to "10:00" and back —
    /// and every menu-bar icon to its left shuffles along with it.
    static let figureSpace = "\u{2007}"

    /// Right-aligned, so the digits nearest the icon stay where they are.
    static func padded(_ text: String, to width: Int) -> String {
        let missing = max(0, width - text.count)
        return String(repeating: figureSpace, count: missing) + text
    }

    /// - Parameters:
    ///   - deadline: the soonest session end, or nil when nothing the user started has an end.
    ///   - endless: something is holding with no end (a trigger, or an uncapped indefinite session).
    ///   - ticking: count in seconds ("12:45") rather than whole minutes ("13m").
    static func text(
        readout: MenuBarReadout,
        isAwake: Bool,
        deadline: Date?,
        endless: Bool,
        now: Date,
        stat: String,
        ticking: Bool = false
    ) -> String {
        func remaining(_ end: Date) -> String {
            let left = end.timeIntervalSince(now)
            guard ticking else { return padded(TimeFormatting.menuBar(remaining: left), to: 5) }
            // "1:45:03" is seven columns, "45:03" five. Padding to the wider of the two only while
            // the session is over an hour means the width changes once, not every time a digit is
            // dropped.
            return padded(TimeFormatting.countdown(left), to: left >= 3600 ? 7 : 5)
        }
        var parts: [String] = []
        if readout != .iconOnly, isAwake {
            switch (deadline, endless) {
            case (let end?, false):
                parts.append(remaining(end))
            case (let end?, true):
                // Honest about both: this session ends then, but the Mac stays awake after it.
                parts.append(remaining(end) + " ∞")
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
