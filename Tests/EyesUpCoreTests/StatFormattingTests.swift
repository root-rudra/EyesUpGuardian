import Foundation
import Testing
@testable import EyesUpCore

@Suite struct StatFormattingTests {
    @Test func bytesUseTheRightUnit() {
        #expect(StatFormatting.bytes(512) == "512 B")
        #expect(StatFormatting.bytes(2048) == "2.0 KB")
        #expect(StatFormatting.bytes(5_500_000) == "5.5 MB")
        #expect(StatFormatting.bytes(41_000_000_000) == "41.0 GB")
        #expect(StatFormatting.bytes(2_500_000_000_000) == "2.5 TB")
    }

    @Test func ratesReadPerSecond() {
        #expect(StatFormatting.rate(0) == "0 B/s")
        #expect(StatFormatting.rate(1_500_000) == "1.5 MB/s")
    }

    @Test func percentsAndUnitsAreShort() {
        #expect(StatFormatting.percent(12.4) == "12%")
        #expect(StatFormatting.percent(99.6) == "100%")
        #expect(StatFormatting.watts(38.44) == "38.4 W")
        #expect(StatFormatting.celsius(57.91) == "58°C")
        #expect(StatFormatting.rpm(996) == "996 rpm")
    }

    @Test func uptimeReadsInDaysAndHours() {
        let now = referenceDate
        #expect(StatFormatting.uptime(since: now.addingTimeInterval(-90), now: now) == "1m")
        #expect(StatFormatting.uptime(since: now.addingTimeInterval(-3 * 3600 - 600), now: now) == "3h 10m")
        #expect(StatFormatting.uptime(since: now.addingTimeInterval(-(6 * 86_400 + 4 * 3600)), now: now) == "6d 4h")
        #expect(StatFormatting.uptime(since: now.addingTimeInterval(60), now: now) == StatFormatting.unavailable)
    }

    @Test func idleReadsAsAwayTime() {
        #expect(StatFormatting.idle(5) == "just now")
        #expect(StatFormatting.idle(2520) == "42m")
    }

    @Test func formattersHandleMissingAndAbsurdValues() {
        #expect(StatFormatting.percent(nil) == StatFormatting.unavailable)
        #expect(StatFormatting.percent(.nan) == StatFormatting.unavailable)
        #expect(StatFormatting.watts(.infinity) == StatFormatting.unavailable)
        #expect(StatFormatting.bytes(nil) == StatFormatting.unavailable)
        #expect(StatFormatting.rate(-5) == StatFormatting.unavailable)
        #expect(StatFormatting.celsius(nil) == StatFormatting.unavailable)
        #expect(StatFormatting.rpm(.nan) == StatFormatting.unavailable)
        #expect(StatFormatting.idle(nil) == StatFormatting.unavailable)
    }

    @Test func thermalLevelsHaveReadableNames() {
        #expect(ThermalLevel.nominal.title == "Normal")
        #expect(ThermalLevel.fair.title == "Warm")
        #expect(ThermalLevel.serious.title == "Hot")
        #expect(ThermalLevel.critical.title == "Too hot")
    }

    @Test func rateSurvivesValuesTooLargeForAnInteger() {
        #expect(StatFormatting.rate(1e30) != "")
        #expect(StatFormatting.rate(Double(UInt64.max)) != "")
        #expect(StatFormatting.rate(1.8e19) != "")
    }
}
