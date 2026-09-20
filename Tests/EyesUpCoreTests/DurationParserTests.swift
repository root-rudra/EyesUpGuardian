import Testing
@testable import EyesUpCore

@Suite struct DurationParserTests {
    @Test(arguments: [
        ("90m", 5400.0), ("2h", 7200.0), ("1h30m", 5400.0), (" 2H ", 7200.0), ("999h", 3_596_400.0), ("1m", 60.0),
    ])
    func parsesValidDurations(text: String, seconds: Double) {
        #expect(DurationParser.parse(text) == .finite(seconds))
    }

    @Test func parsesInfinity() {
        #expect(DurationParser.parse("inf") == .infinite)
        #expect(DurationParser.parse(" INF ") == .infinite)
    }

    @Test(arguments: ["", " ", "0m", "0h0m", "h", "m", "1h1h", "-5m", "1000h", "12345m", "1.5h", "٣h", "2d", "30", "1h30m5s"])
    func rejectsInvalidDurations(text: String) {
        #expect(DurationParser.parse(text) == nil)
    }

    @Test(arguments: ["1h 30m", " 2h 15m ", "1h  5m"])
    func acceptsTheSpacedFormTheAppItselfPrints(text: String) {
        #expect(DurationParser.parse(text) != nil)
    }

    @Test func stillRejectsTheThingsItShould() {
        #expect(DurationParser.parse("1h 30") == nil)
        #expect(DurationParser.parse("h m") == nil)
        #expect(DurationParser.parse("1 h 30 m") == nil)
    }
}
