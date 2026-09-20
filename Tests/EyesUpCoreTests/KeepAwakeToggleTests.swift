import Foundation
import Testing
@testable import EyesUpCore

@Suite @MainActor struct KeepAwakeToggleTests {
    private func hold(_ source: HoldSource) -> Hold {
        Hold(source: source, label: "x", policy: .system, end: .indefinite, createdAt: referenceDate)
    }

    @Test func stoppingComesFirstWhenTheUserStartedSomething() {
        let holds = [hold(.manual), hold(.trigger(UUID()))]
        #expect(KeepAwakeToggle.next(holds: holds, triggersPaused: false) == .stopManualSessions)
    }

    /// Regression: with only a trigger holding, the toggle called stopAll(), which spares trigger
    /// holds — so the shortcut did nothing, twice in a row, with no way to tell.
    @Test func aTriggerHoldIsPausedRatherThanIgnored() {
        #expect(KeepAwakeToggle.next(holds: [hold(.trigger(UUID()))], triggersPaused: false) == .pauseTriggers)
    }

    @Test func pausedTriggersResumeBeforeAManualSessionIsStarted() {
        #expect(KeepAwakeToggle.next(holds: [], triggersPaused: true) == .resumeTriggers)
    }

    @Test func nothingRunningStartsAnIndefiniteSession() {
        #expect(KeepAwakeToggle.next(holds: [], triggersPaused: false) == .startIndefinite)
    }
}
