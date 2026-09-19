import Foundation
import Testing
@testable import EyesUpCore

@Suite @MainActor struct EventMonitorTests {
    let clock = FakeClock()
    let scheduler = FakeScheduler()

    // MARK: Apps

    @Test func appMonitorReportsWhileAnyChosenAppIsOpen() {
        let workspace = FakeWorkspace()
        workspace.running = ["com.apple.Terminal"]
        let monitor = AppRunningMonitor(bundleIDs: ["com.anthropic.claudefordesktop", "com.apple.Terminal"], workspace: workspace)
        var answers: [Bool] = []
        monitor.start { answers.append($0) }
        #expect(answers == [true])

        workspace.change(to: ["com.apple.Finder"])
        #expect(answers == [true, false])

        workspace.change(to: ["com.anthropic.claudefordesktop"])
        #expect(answers == [true, false, true])
    }

    @Test func appMonitorStopsListening() {
        let workspace = FakeWorkspace()
        let monitor = AppRunningMonitor(bundleIDs: ["com.apple.Terminal"], workspace: workspace)
        var count = 0
        monitor.start { _ in count += 1 }
        monitor.stop()
        workspace.change(to: ["com.apple.Terminal"])
        #expect(count == 1) // only the initial answer
    }

    // MARK: Displays

    @Test func displayMonitorMatchesOnVendorModelSerial() {
        let studioDisplay = DisplayMatch(vendor: 7789, model: 30734, serial: 47852, name: "LG UltraFine")
        let otherDisplay = DisplayMatch(vendor: 1, model: 2, serial: 3, name: "Other")
        let displays = FakeDisplays()
        displays.connected = [otherDisplay]
        let monitor = DisplayConnectedMonitor(match: studioDisplay, displays: displays)
        var answers: [Bool] = []
        monitor.start { answers.append($0) }
        #expect(answers == [false])

        displays.change(to: [otherDisplay, DisplayMatch(vendor: 7789, model: 30734, serial: 47852, name: "renamed")])
        #expect(answers == [false, true])
    }

    // MARK: Power

    @Test func powerMonitorFollowsTheSource() {
        let power = FakePowerSource()
        power.onAC = false
        let monitor = PowerSourceMonitor(power: power)
        var answers: [Bool] = []
        monitor.start { answers.append($0) }
        #expect(answers == [false])

        power.change(to: true)
        #expect(answers == [false, true])
    }

    // MARK: Schedule

    /// 2026-09-21 09:00 local, a Monday.
    private func mondayMorning() -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 8, minute: 0))!
    }

    private func newYork() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    @Test func scheduleMonitorReportsAndArmsTheNextBoundary() {
        clock.now = mondayMorning()
        let schedule = Schedule(weekdays: [2, 3, 4, 5, 6], startMinute: 9 * 60, endMinute: 18 * 60)
        let calendar = newYork()
        let monitor = ScheduleMonitor(schedule: schedule, clock: clock, scheduler: scheduler, calendar: { calendar })
        var answers: [Bool] = []
        monitor.start { answers.append($0) }
        #expect(answers == [false])

        clock.advance(3600) // 09:00
        scheduler.runDue(at: clock.now)
        #expect(answers == [false, true])
    }

    @Test func scheduleMonitorReevaluatesOnDemand() {
        clock.now = mondayMorning()
        let schedule = Schedule(weekdays: [2, 3, 4, 5, 6], startMinute: 9 * 60, endMinute: 18 * 60)
        let calendar = newYork()
        let monitor = ScheduleMonitor(schedule: schedule, clock: clock, scheduler: scheduler, calendar: { calendar })
        var answers: [Bool] = []
        monitor.start { answers.append($0) }

        clock.advance(7200) // the Mac slept past 09:00; no timer fired
        monitor.reevaluate()
        #expect(answers == [false, true])
    }

    @Test func scheduleMonitorStopsItsTimer() {
        clock.now = mondayMorning()
        let calendar = newYork()
        let monitor = ScheduleMonitor(schedule: Schedule(weekdays: [2], startMinute: 9 * 60, endMinute: 18 * 60),
                                      clock: clock, scheduler: scheduler, calendar: { calendar })
        monitor.start { _ in }
        monitor.stop()
        #expect(scheduler.pending.isEmpty)
    }
}
