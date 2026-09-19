import Foundation

extension Schedule {
    /// True when `date` falls inside a window that started on one of the selected weekdays.
    public func isActive(at date: Date, calendar: Calendar) -> Bool {
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        let weekday = calendar.component(.weekday, from: date)

        if startMinute < endMinute {
            return weekdays.contains(weekday) && minute >= startMinute && minute < endMinute
        }
        // The window crosses midnight, so it belongs to the day it started on.
        if weekdays.contains(weekday) && minute >= startMinute { return true }
        let previousDay = weekday == 1 ? 7 : weekday - 1
        return weekdays.contains(previousDay) && minute < endMinute
    }

    /// The next moment `isActive` can change, or nil if it never does.
    /// Looks 8 days ahead so a once-a-week window always has a boundary.
    public func nextBoundary(after date: Date, calendar: Calendar) -> Date? {
        var candidates: [Date] = []
        for dayOffset in 0...8 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: date) else { continue }
            for minute in [startMinute, endMinute] {
                // On a DST spring-forward day the wall time may not exist; Calendar moves to the next valid time.
                guard let candidate = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day),
                      candidate > date else { continue }
                candidates.append(candidate)
            }
        }
        return candidates.min()
    }
}
