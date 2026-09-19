import EyesUpCore
import Foundation

/// The editable form behind the trigger sheet. `makeTrigger()` returns a validated trigger, or nil
/// when the form isn't usable yet, so the Save button can stay disabled.
@MainActor
@Observable
final class TriggerDraft: Identifiable {
    enum Kind: String, CaseIterable, Identifiable, Hashable {
        case appRunning, processRunning, schedule, cpuBusy, networkBusy, diskBusy, displayConnected, onACPower

        var id: String { rawValue }

        var title: String {
            switch self {
            case .appRunning: "While an app is open"
            case .processRunning: "While a command is running"
            case .schedule: "On a schedule"
            case .cpuBusy: "While the CPU is busy"
            case .networkBusy: "While the network is busy"
            case .diskBusy: "While the disk is busy"
            case .displayConnected: "While a display is connected"
            case .onACPower: "While on AC power"
            }
        }
    }

    let id: UUID
    let isNew: Bool
    var kind: Kind
    var name = ""
    var bundleIDs: [String] = []
    /// Comma separated, e.g. "node, claude".
    var processNames = ""
    var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    var startMinute = 9 * 60
    var endMinute = 18 * 60
    var cpuPercent = 40.0
    var megabytesPerSecond = 1.0
    var sustainMinutes = 2.0
    var releaseMinutes = 5.0
    var display: DisplayMatch?
    var keepDisplayOn = false
    var graceMinutes = 5.0
    var notifyOnChange = false
    var isEnabled = true

    init(kind: Kind = .appRunning) {
        id = UUID()
        isNew = true
        self.kind = kind
    }

    init(trigger: Trigger) {
        id = trigger.id
        isNew = false
        name = trigger.name
        keepDisplayOn = trigger.policy.contains(.display)
        graceMinutes = trigger.grace / 60
        notifyOnChange = trigger.notifyOnChange
        isEnabled = trigger.isEnabled

        switch trigger.condition {
        case .appRunning(let ids):
            kind = .appRunning
            bundleIDs = ids
        case .processRunning(let names):
            kind = .processRunning
            processNames = names.joined(separator: ", ")
        case .schedule(let schedule):
            kind = .schedule
            weekdays = schedule.weekdays
            startMinute = schedule.startMinute
            endMinute = schedule.endMinute
        case .cpuBusy(let threshold):
            kind = .cpuBusy
            cpuPercent = threshold.value
            sustainMinutes = threshold.sustain / 60
            releaseMinutes = threshold.release / 60
        case .networkBusy(let threshold):
            kind = .networkBusy
            megabytesPerSecond = threshold.value / 1_000_000
            sustainMinutes = threshold.sustain / 60
            releaseMinutes = threshold.release / 60
        case .diskBusy(let threshold):
            kind = .diskBusy
            megabytesPerSecond = threshold.value / 1_000_000
            sustainMinutes = threshold.sustain / 60
            releaseMinutes = threshold.release / 60
        case .displayConnected(let match):
            kind = .displayConnected
            display = match
        case .onACPower:
            kind = .onACPower
        }
    }

    var defaultName: String { kind.title }

    func makeTrigger() -> Trigger? {
        let sustain = sustainMinutes * 60
        let release = releaseMinutes * 60
        let condition: TriggerCondition

        switch kind {
        case .appRunning:
            condition = .appRunning(bundleIDs: bundleIDs)
        case .processRunning:
            let names = processNames.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            condition = .processRunning(names: names)
        case .schedule:
            condition = .schedule(Schedule(weekdays: weekdays, startMinute: startMinute, endMinute: endMinute))
        case .cpuBusy:
            condition = .cpuBusy(ActivityThreshold(value: cpuPercent.rounded(), sustain: sustain, release: release))
        case .networkBusy:
            condition = .networkBusy(ActivityThreshold(value: megabytesPerSecond * 1_000_000, sustain: sustain, release: release))
        case .diskBusy:
            condition = .diskBusy(ActivityThreshold(value: megabytesPerSecond * 1_000_000, sustain: sustain, release: release))
        case .displayConnected:
            guard let display else { return nil }
            condition = .displayConnected(display)
        case .onACPower:
            condition = .onACPower
        }

        return TriggerValidator.sanitized(Trigger(
            id: id,
            name: name.trimmingCharacters(in: .whitespaces).isEmpty ? defaultName : name,
            condition: condition,
            policy: keepDisplayOn ? [.system, .display] : .system,
            grace: graceMinutes * 60,
            notifyOnChange: notifyOnChange,
            isEnabled: isEnabled
        ))
    }
}
