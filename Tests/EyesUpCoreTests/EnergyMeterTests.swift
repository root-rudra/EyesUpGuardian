import Foundation
import Testing
@testable import EyesUpCore

// `#expect`/`#require` capture their argument immutably, so each mutating call runs first.
@Suite struct EnergyMeterTests {
    @Test func firstSampleOnlySetsABaseline() {
        var meter = EnergyMeter()
        let first = meter.accumulate(watts: 40, at: referenceDate, awake: true)
        #expect(first == nil)
    }

    @Test func steadyDrawIntegratesToKilowattHours() throws {
        var meter = EnergyMeter()
        _ = meter.accumulate(watts: 36, at: referenceDate, awake: true)
        // 36 W for 100 s = 1 Wh = 0.001 kWh
        let result = meter.accumulate(watts: 36, at: referenceDate.addingTimeInterval(100), awake: true)
        let tick = try #require(result)
        #expect(abs(tick.kilowattHours - 0.001) < 0.000_001)
        #expect(tick.awakeSeconds == 100)
    }

    @Test func timeWhileNotAwakeCountsEnergyButNotAwakeSeconds() throws {
        var meter = EnergyMeter()
        _ = meter.accumulate(watts: 36, at: referenceDate, awake: false)
        let result = meter.accumulate(watts: 36, at: referenceDate.addingTimeInterval(100), awake: false)
        let tick = try #require(result)
        #expect(tick.kilowattHours > 0)
        #expect(tick.awakeSeconds == 0)
    }

    @Test func sleepGapsDoNotCountAsEnergy() {
        var meter = EnergyMeter()
        _ = meter.accumulate(watts: 36, at: referenceDate, awake: true)
        // The Mac slept for an hour: nothing was measured in between, so nothing is claimed.
        let acrossTheGap = meter.accumulate(watts: 36, at: referenceDate.addingTimeInterval(3600), awake: true)
        let afterwards = meter.accumulate(watts: 36, at: referenceDate.addingTimeInterval(3630), awake: true)
        #expect(acrossTheGap == nil)
        #expect(afterwards != nil)
    }

    @Test func clockGoingBackwardsIsIgnored() {
        var meter = EnergyMeter()
        _ = meter.accumulate(watts: 36, at: referenceDate, awake: true)
        let backwards = meter.accumulate(watts: 36, at: referenceDate.addingTimeInterval(-60), awake: true)
        #expect(backwards == nil)
    }

    @Test func absurdWattsAreIgnored() {
        var meter = EnergyMeter()
        _ = meter.accumulate(watts: 36, at: referenceDate, awake: true)
        let notANumber = meter.accumulate(watts: .nan, at: referenceDate.addingTimeInterval(30), awake: true)
        let impossible = meter.accumulate(watts: 50_000, at: referenceDate.addingTimeInterval(60), awake: true)
        #expect(notANumber == nil)
        #expect(impossible == nil)
    }

    @Test func energySplitsAcrossMidnight() throws {
        // A tick is attributed to the moment it ended, so day buckets stay simple and a Mac left
        // awake overnight doesn't pile the whole night onto one day.
        var meter = EnergyMeter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let beforeMidnight = calendar.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 23, minute: 59, second: 30))!
        _ = meter.accumulate(watts: 36, at: beforeMidnight, awake: true)
        let result = meter.accumulate(watts: 36, at: beforeMidnight.addingTimeInterval(60), awake: true)
        let tick = try #require(result)
        #expect(calendar.component(.day, from: tick.at) == 22)
    }

    @Test func costNeedsARate() {
        #expect(EnergyCost.money(1.5, ratePerKilowattHour: nil, locale: Locale(identifier: "en_US")) == nil)
        let cost = EnergyCost.money(1.5, ratePerKilowattHour: 0.32, locale: Locale(identifier: "en_US"))
        #expect(cost?.contains("0.48") == true)
        #expect(EnergyCost.money(.nan, ratePerKilowattHour: 0.32, locale: Locale(identifier: "en_US")) == nil)
        #expect(EnergyCost.money(1, ratePerKilowattHour: -1, locale: Locale(identifier: "en_US")) == nil)
    }
}
