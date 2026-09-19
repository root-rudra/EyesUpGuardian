import EyesUpCore
import Foundation
import Testing
@testable import EyesUpApp

@Suite @MainActor struct TriggerDraftTests {
    @Test func newDraftBecomesAValidTrigger() throws {
        let draft = TriggerDraft(kind: .appRunning)
        draft.bundleIDs = ["com.anthropic.claudefordesktop"]
        draft.name = "Claude running"
        draft.graceMinutes = 5
        draft.keepDisplayOn = true

        let trigger = try #require(draft.makeTrigger())
        #expect(trigger.name == "Claude running")
        #expect(trigger.condition == .appRunning(bundleIDs: ["com.anthropic.claudefordesktop"]))
        #expect(trigger.grace == 300)
        #expect(trigger.policy == [.system, .display])
    }

    @Test func anEmptyNameFallsBackToTheKindTitle() throws {
        let draft = TriggerDraft(kind: .onACPower)
        let trigger = try #require(draft.makeTrigger())
        #expect(trigger.name == TriggerDraft.Kind.onACPower.title)
    }

    @Test func megabytesConvertToBytesPerSecond() throws {
        let draft = TriggerDraft(kind: .networkBusy)
        draft.megabytesPerSecond = 2.5
        draft.sustainMinutes = 1
        draft.releaseMinutes = 3
        let trigger = try #require(draft.makeTrigger())
        #expect(trigger.condition == .networkBusy(ActivityThreshold(value: 2_500_000, sustain: 60, release: 180)))
    }

    @Test func processNamesAreSplitOnCommas() throws {
        let draft = TriggerDraft(kind: .processRunning)
        draft.processNames = " node , claude,, swift-build "
        let trigger = try #require(draft.makeTrigger())
        #expect(trigger.condition == .processRunning(names: ["node", "claude", "swift-build"]))
    }

    @Test func incompleteDraftsMakeNoTrigger() {
        #expect(TriggerDraft(kind: .appRunning).makeTrigger() == nil)          // no apps chosen
        #expect(TriggerDraft(kind: .processRunning).makeTrigger() == nil)      // no names typed
        #expect(TriggerDraft(kind: .displayConnected).makeTrigger() == nil)    // no display chosen
        let outOfRange = TriggerDraft(kind: .cpuBusy)
        outOfRange.cpuPercent = 0
        #expect(outOfRange.makeTrigger() == nil)
    }

    @Test func editingKeepsTheTriggerIdentity() throws {
        let original = Trigger(name: "Weekdays", condition: .schedule(Schedule(weekdays: [2, 3], startMinute: 540, endMinute: 1080)),
                               policy: .system, grace: 600, notifyOnChange: true, isEnabled: false)
        let draft = TriggerDraft(trigger: original)
        #expect(draft.kind == .schedule)
        #expect(draft.weekdays == [2, 3])
        #expect(draft.graceMinutes == 10)
        #expect(!draft.isEnabled)

        let rebuilt = try #require(draft.makeTrigger())
        #expect(rebuilt.id == original.id)
        #expect(rebuilt == original)
    }
}
