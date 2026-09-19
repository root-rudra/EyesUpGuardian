import Foundation
import Testing
@testable import EyesUpCore

@Suite struct TimeFormattingTests {
    @Test func durationLabels() {
        #expect(TimeFormatting.duration(7200) == "2h")
        #expect(TimeFormatting.duration(5400) == "1h 30m")
        #expect(TimeFormatting.duration(900) == "15m")
        #expect(TimeFormatting.duration(20) == "<1m")
    }

    @Test func menuBarReadout() {
        #expect(TimeFormatting.menuBar(remaining: 6120) == "1:42")
        #expect(TimeFormatting.menuBar(remaining: 3600) == "1:00")
        #expect(TimeFormatting.menuBar(remaining: 2519) == "42m")
        #expect(TimeFormatting.menuBar(remaining: 30) == "1m")
        #expect(TimeFormatting.menuBar(remaining: -5) == "0m")
    }

    @Test func countdown() {
        #expect(TimeFormatting.countdown(6130) == "1:42:10")
        #expect(TimeFormatting.countdown(2530) == "42:10")
        #expect(TimeFormatting.countdown(-1) == "0:00")
    }

    @Test func remainingFractionIsClamped() {
        let start = referenceDate
        let end = start.addingTimeInterval(100)
        #expect(TimeFormatting.remainingFraction(now: start.addingTimeInterval(25), start: start, end: end) == 0.75)
        #expect(TimeFormatting.remainingFraction(now: end.addingTimeInterval(10), start: start, end: end) == 0)
        #expect(TimeFormatting.remainingFraction(now: start.addingTimeInterval(-10), start: start, end: end) == 1)
        #expect(TimeFormatting.remainingFraction(now: start, start: start, end: start) == 0)
    }
}
