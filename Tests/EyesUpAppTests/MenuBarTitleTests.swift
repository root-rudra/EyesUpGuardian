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
        #expect(text.hasSuffix("45m ∞"))
    }

    @Test func aPlainTimerReadsAsTheTimeLeft() {
        #expect(MenuBarTitle.text(readout: .timer, isAwake: true, deadline: inMinutes(45),
                                  endless: false, now: now, stat: "").hasSuffix("45m"))
        #expect(MenuBarTitle.text(readout: .timer, isAwake: true, deadline: inMinutes(125),
                                  endless: false, now: now, stat: "").hasSuffix("2:05"))
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

    /// The item must not change width as digits come and go, or every icon to its left shuffles.
    @Test func theWidthHoldsStillAsTheDigitsChange() {
        func width(_ seconds: Double, ticking: Bool) -> Int {
            MenuBarTitle.text(readout: .timer, isAwake: true, deadline: now.addingTimeInterval(seconds),
                              endless: false, now: now, stat: "", ticking: ticking).count
        }
        // Under an hour, ticking: 9:59 → 10:00 → 59:59 all occupy the same columns.
        #expect(width(599, ticking: true) == width(600, ticking: true))
        #expect(width(599, ticking: true) == width(3599, ticking: true))
        #expect(width(59, ticking: true) == width(3599, ticking: true))
        // Whole minutes: 9m → 10m → 1:00 likewise.
        #expect(width(540, ticking: false) == width(600, ticking: false))
        #expect(width(540, ticking: false) == width(3600, ticking: false))
    }

    @Test func tickingReadsAsAClock() {
        #expect(MenuBarTitle.text(readout: .timer, isAwake: true, deadline: now.addingTimeInterval(765),
                                  endless: false, now: now, stat: "", ticking: true).hasSuffix("12:45"))
        #expect(MenuBarTitle.text(readout: .timer, isAwake: true, deadline: now.addingTimeInterval(6303),
                                  endless: false, now: now, stat: "", ticking: true).hasSuffix("1:45:03"))
        // Still honest about something endless holding after this session.
        #expect(MenuBarTitle.text(readout: .timer, isAwake: true, deadline: now.addingTimeInterval(765),
                                  endless: true, now: now, stat: "", ticking: true).hasSuffix("12:45 ∞"))
        // Nothing to count: the clock setting changes no other answer.
        #expect(MenuBarTitle.text(readout: .timer, isAwake: true, deadline: nil,
                                  endless: true, now: now, stat: "", ticking: true) == " ∞")
    }

    @Test func statsSitAfterTheTimeWithASeparator() {
        #expect(MenuBarTitle.text(readout: .timerCPUAndPower, isAwake: true, deadline: inMinutes(45),
                                  endless: false, now: now, stat: "12% · 38.4 W").hasSuffix("45m · 12% · 38.4 W"))
        // A stat readout while idle still shows its stat.
        #expect(MenuBarTitle.text(readout: .timerAndCPU, isAwake: false, deadline: nil,
                                  endless: false, now: now, stat: "12%") == " 12%")
    }
}
