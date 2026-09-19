import Foundation
import Testing
@testable import EyesUpCore

@Suite struct TriggerModelTests {
    @Test func triggersRoundTripThroughJSON() throws {
        let triggers = [
            makeTrigger(condition: .appRunning(bundleIDs: ["com.anthropic.claudefordesktop"])),
            makeTrigger(condition: .processRunning(names: ["node"]), grace: 300),
            makeTrigger(condition: .schedule(Schedule(weekdays: [2, 3], startMinute: 540, endMinute: 1080))),
            makeTrigger(condition: .cpuBusy(ActivityThreshold(value: 40))),
            makeTrigger(condition: .networkBusy(ActivityThreshold(value: 1_000_000))),
            makeTrigger(condition: .diskBusy(ActivityThreshold(value: 20_000_000))),
            makeTrigger(condition: .displayConnected(DisplayMatch(vendor: 7789, model: 30734, serial: 47852, name: "LG"))),
            makeTrigger(condition: .onACPower, notifyOnChange: true, isEnabled: false),
        ]
        let data = try JSONEncoder().encode(triggers)
        #expect(try JSONDecoder().decode([Trigger].self, from: data) == triggers)
    }

    @Test func sanitizedTrimsAndKeepsValidTriggers() throws {
        let trigger = makeTrigger(name: "  Claude running  ", condition: .appRunning(bundleIDs: [" com.anthropic.claudefordesktop ", "com.anthropic.claudefordesktop", ""]))
        let clean = try #require(TriggerValidator.sanitized(trigger))
        #expect(clean.name == "Claude running")
        #expect(clean.condition == .appRunning(bundleIDs: ["com.anthropic.claudefordesktop"]))
    }

    @Test func sanitizedRejectsOutOfRangeValues() {
        #expect(TriggerValidator.sanitized(makeTrigger(name: "   ")) == nil)
        #expect(TriggerValidator.sanitized(makeTrigger(grace: -1)) == nil)
        #expect(TriggerValidator.sanitized(makeTrigger(grace: 86_401)) == nil)
        #expect(TriggerValidator.sanitized(makeTrigger(policy: SleepPolicy(rawValue: 1 << 9))) == nil)
        #expect(TriggerValidator.sanitized(makeTrigger(condition: .appRunning(bundleIDs: []))) == nil)
        #expect(TriggerValidator.sanitized(makeTrigger(condition: .processRunning(names: [String(repeating: "x", count: 300)]))) == nil)
        #expect(TriggerValidator.sanitized(makeTrigger(condition: .cpuBusy(ActivityThreshold(value: 0)))) == nil)
        #expect(TriggerValidator.sanitized(makeTrigger(condition: .cpuBusy(ActivityThreshold(value: 101)))) == nil)
        #expect(TriggerValidator.sanitized(makeTrigger(condition: .cpuBusy(ActivityThreshold(value: 50, sustain: 90_000)))) == nil)
        #expect(TriggerValidator.sanitized(makeTrigger(condition: .networkBusy(ActivityThreshold(value: 10)))) == nil)
        #expect(TriggerValidator.sanitized(makeTrigger(condition: .networkBusy(ActivityThreshold(value: .infinity)))) == nil)
        #expect(TriggerValidator.sanitized(makeTrigger(condition: .schedule(Schedule(weekdays: [], startMinute: 0, endMinute: 60)))) == nil)
        #expect(TriggerValidator.sanitized(makeTrigger(condition: .schedule(Schedule(weekdays: [9], startMinute: 0, endMinute: 60)))) == nil)
        #expect(TriggerValidator.sanitized(makeTrigger(condition: .schedule(Schedule(weekdays: [2], startMinute: 600, endMinute: 600)))) == nil)
        #expect(TriggerValidator.sanitized(makeTrigger(condition: .schedule(Schedule(weekdays: [2], startMinute: -1, endMinute: 60)))) == nil)
        #expect(TriggerValidator.sanitized(makeTrigger(condition: .displayConnected(DisplayMatch(vendor: 0, model: 0, serial: 0, name: "?")))) == nil)
    }

    @Test func sanitizedCapsIdentifierCountAndMasksPolicy() throws {
        let many = (0..<40).map { "com.example.app\($0)" }
        let clean = try #require(TriggerValidator.sanitized(makeTrigger(
            condition: .appRunning(bundleIDs: many),
            policy: SleepPolicy(rawValue: SleepPolicy.system.rawValue | 1 << 9)
        )))
        guard case .appRunning(let ids) = clean.condition else { Issue.record("wrong condition"); return }
        #expect(ids.count == TriggerValidator.maxIdentifiers)
        #expect(clean.policy == .system)
    }

    @Test func summaryDescribesTheCondition() {
        #expect(makeTrigger(condition: .onACPower).summary == "While on AC power")
        #expect(makeTrigger(condition: .processRunning(names: ["node", "claude"])).summary == "While node or claude is running")
        #expect(makeTrigger(condition: .cpuBusy(ActivityThreshold(value: 40, sustain: 120))).summary == "While CPU is above 40% for 2m")
    }

    @Test func suggestsRunningKnownAppsThatHaveNoTriggerYet() {
        let running: Set<String> = ["com.anthropic.claudefordesktop", "com.apple.Terminal", "com.example.other"]
        let existing = [makeTrigger(condition: .appRunning(bundleIDs: ["com.apple.Terminal"]))]
        let suggestions = TriggerSuggestions.suggestions(running: running, existing: existing)
        #expect(suggestions.map(\.bundleID) == ["com.anthropic.claudefordesktop"])
        #expect(suggestions.first?.displayName == "Claude")
        #expect(TriggerSuggestions.suggestions(running: [], existing: []).isEmpty)
    }

    @Test func activityTimingsGetAFloorSoTriggersCannotFlap() throws {
        let trigger = makeTrigger(condition: .cpuBusy(ActivityThreshold(value: 50, sustain: 0, release: 0)))
        let clean = try #require(TriggerValidator.sanitized(trigger))
        guard case .cpuBusy(let threshold) = clean.condition else { Issue.record("wrong condition"); return }
        #expect(threshold.sustain == TriggerValidator.minActivityTiming)
        #expect(threshold.release == TriggerValidator.minActivityTiming)
    }
}
