import Foundation
import Testing
@testable import EyesUpApp
@testable import EyesUpCore

@Suite @MainActor struct MenuBarTitleTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private func inMinutes(_ minutes: Double) -> Date { now.addingTimeInterval(minutes * 60) }

    /// Regression: with a trigger holding, "Icon and time left" showed nothing at all, although a
    /// 45-minute session was running.
    @Test func aTriggerHoldingDoesNotEmptyTheReadout() {
        let text = MenuBarTitle.text(readout: .timer, isAwake: true, deadline: inMinutes(45),
                                     endless: true, now: now, stat: "")
        #expect(text == " 45m ∞")
    }

    @Test func aPlainTimerReadsAsTheTimeLeft() {
        #expect(MenuBarTitle.text(readout: .timer, isAwake: true, deadline: inMinutes(45),
                                  endless: false, now: now, stat: "") == " 45m")
        #expect(MenuBarTitle.text(readout: .timer, isAwake: true, deadline: inMinutes(125),
                                  endless: false, now: now, stat: "") == " 2:05")
    }

    /// Nothing ends and nothing may sleep: say so, rather than leaving the promise unkept.
    @Test func anEndlessHoldReadsAsInfinity() {
        #expect(MenuBarTitle.text(readout: .timer, isAwake: true, deadline: nil,
                                  endless: true, now: now, stat: "") == " ∞")
    }

    @Test func idleShowsNothingAtAll() {
        #expect(MenuBarTitle.text(readout: .timer, isAwake: false, deadline: nil,
                                  endless: false, now: now, stat: "").isEmpty)
        #expect(MenuBarTitle.text(readout: .iconOnly, isAwake: true, deadline: inMinutes(45),
                                  endless: false, now: now, stat: "").isEmpty)
    }

    @Test func statsSitAfterTheTimeWithASeparator() {
        #expect(MenuBarTitle.text(readout: .timerCPUAndPower, isAwake: true, deadline: inMinutes(45),
                                  endless: false, now: now, stat: "12% · 38.4 W") == " 45m · 12% · 38.4 W")
        // A stat readout while idle still shows its stat.
        #expect(MenuBarTitle.text(readout: .timerAndCPU, isAwake: false, deadline: nil,
                                  endless: false, now: now, stat: "12%") == " 12%")
    }
}
