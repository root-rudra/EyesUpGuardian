import Foundation
import Testing
@testable import EyesUpCore

@Suite struct ScheduleTests {
    private func calendar(_ identifier: String = "America/New_York") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// Weekdays 09:00–18:00. 2026-09-21 is a Monday.
    private let workdays = Schedule(weekdays: [2, 3, 4, 5, 6], startMinute: 9 * 60, endMinute: 18 * 60)

    @Test func activeInsideTheWindowOnSelectedDays() {
        let calendar = calendar()
        #expect(workdays.isActive(at: date(2026, 9, 21, 10, 0, in: calendar), calendar: calendar))
        #expect(!workdays.isActive(at: date(2026, 9, 21, 8, 59, in: calendar), calendar: calendar))
        #expect(workdays.isActive(at: date(2026, 9, 21, 9, 0, in: calendar), calendar: calendar))
        #expect(!workdays.isActive(at: date(2026, 9, 21, 18, 0, in: calendar), calendar: calendar))
        #expect(!workdays.isActive(at: date(2026, 9, 20, 10, 0, in: calendar), calendar: calendar)) // Sunday
    }

    @Test func crossesMidnight() {
        let calendar = calendar()
        // Friday 22:00 until 02:00 the next morning.
        let nightShift = Schedule(weekdays: [6], startMinute: 22 * 60, endMinute: 2 * 60)
        #expect(nightShift.isActive(at: date(2026, 9, 25, 23, 30, in: calendar), calendar: calendar)) // Fri night
        #expect(nightShift.isActive(at: date(2026, 9, 26, 1, 30, in: calendar), calendar: calendar))  // Sat 01:30
        #expect(!nightShift.isActive(at: date(2026, 9, 26, 2, 0, in: calendar), calendar: calendar))  // Sat 02:00
        #expect(!nightShift.isActive(at: date(2026, 9, 26, 23, 0, in: calendar), calendar: calendar)) // Sat night
        #expect(!nightShift.isActive(at: date(2026, 9, 25, 21, 0, in: calendar), calendar: calendar)) // Fri 21:00
    }

    @Test func nextBoundaryFollowsTheCalendar() {
        let calendar = calendar()
        let monday8 = date(2026, 9, 21, 8, 0, in: calendar)
        #expect(workdays.nextBoundary(after: monday8, calendar: calendar) == date(2026, 9, 21, 9, 0, in: calendar))
        let monday10 = date(2026, 9, 21, 10, 0, in: calendar)
        #expect(workdays.nextBoundary(after: monday10, calendar: calendar) == date(2026, 9, 21, 18, 0, in: calendar))
    }

    @Test func springForwardHasABoundary() {
        // 2026-03-08: US clocks jump 02:00 → 03:00, so 02:30 does not exist that day.
        let calendar = calendar()
        let nightly = Schedule(weekdays: [1, 2, 3, 4, 5, 6, 7], startMinute: 2 * 60 + 30, endMinute: 4 * 60)
        let before = date(2026, 3, 8, 1, 0, in: calendar)
        let boundary = nightly.nextBoundary(after: before, calendar: calendar)
        #expect(boundary != nil)
        #expect((boundary ?? before) > before)
    }

    @Test func timeZoneChangesTheAnswer() {
        let newYork = calendar()
        let tokyo = calendar("Asia/Tokyo")
        let instant = date(2026, 9, 21, 10, 0, in: newYork) // 23:00 in Tokyo
        #expect(workdays.isActive(at: instant, calendar: newYork))
        #expect(!workdays.isActive(at: instant, calendar: tokyo))
    }
}
