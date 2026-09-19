import Foundation
import Testing
@testable import EyesUpCore

// `#expect` captures its argument immutably, so each mutating call is made first and the result asserted.
@Suite struct ActivityGateTests {
    private let threshold = ActivityThreshold(value: 40, sustain: 120, release: 300)

    @Test func turnsOnOnlyAfterSustainedActivity() {
        var gate = ActivityGate(threshold: threshold)
        let first = gate.update(value: 90, at: referenceDate)
        let second = gate.update(value: 90, at: referenceDate.addingTimeInterval(60))
        let third = gate.update(value: 90, at: referenceDate.addingTimeInterval(120))
        #expect(!first)
        #expect(!second)
        #expect(third)
        #expect(gate.isOn)
    }

    @Test func gateIgnoresBriefSpikes() {
        var gate = ActivityGate(threshold: threshold)
        let spike = gate.update(value: 95, at: referenceDate)
        let dip = gate.update(value: 5, at: referenceDate.addingTimeInterval(15))
        let spikeAgain = gate.update(value: 95, at: referenceDate.addingTimeInterval(30))
        let later = gate.update(value: 95, at: referenceDate.addingTimeInterval(100))
        #expect(!spike)
        #expect(!dip)
        #expect(!spikeAgain)
        #expect(!later) // the sustain window restarted after the dip
    }

    @Test func gateHoldsThroughBriefDips() {
        var gate = ActivityGate(threshold: threshold)
        _ = gate.update(value: 90, at: referenceDate)
        _ = gate.update(value: 90, at: referenceDate.addingTimeInterval(120))
        #expect(gate.isOn)

        let duringDip = gate.update(value: 1, at: referenceDate.addingTimeInterval(180))
        let busyAgain = gate.update(value: 90, at: referenceDate.addingTimeInterval(240))
        let quiet = gate.update(value: 1, at: referenceDate.addingTimeInterval(300))
        let longQuiet = gate.update(value: 1, at: referenceDate.addingTimeInterval(601))
        #expect(duringDip)
        #expect(busyAgain)
        #expect(quiet)
        #expect(!longQuiet)
    }

    @Test func zeroSustainTurnsOnAtOnce() {
        var gate = ActivityGate(threshold: ActivityThreshold(value: 10, sustain: 0, release: 0))
        let on = gate.update(value: 50, at: referenceDate)
        let off = gate.update(value: 1, at: referenceDate.addingTimeInterval(1))
        #expect(on)
        #expect(!off)
    }

    @Test func rateMeterNeedsTwoSamplesAndIgnoresCounterResets() {
        var meter = RateMeter()
        let first = meter.rate(for: 1000, at: referenceDate)
        let second = meter.rate(for: 3000, at: referenceDate.addingTimeInterval(2))
        let afterReset = meter.rate(for: 10, at: referenceDate.addingTimeInterval(4))
        let afterwards = meter.rate(for: 20, at: referenceDate.addingTimeInterval(6))
        let sameInstant = meter.rate(for: 30, at: referenceDate.addingTimeInterval(6))
        #expect(first == nil)
        #expect(second == 1000)
        #expect(afterReset == nil)
        #expect(afterwards == 5)
        #expect(sameInstant == nil)
    }

    @Test func cpuMeterConvertsTicksToPercent() {
        var meter = CPUMeter()
        let first = meter.percent(busy: 100, total: 1000)
        let second = meter.percent(busy: 150, total: 1100)
        let noNewTicks = meter.percent(busy: 150, total: 1100)
        #expect(first == nil)
        #expect(second == 50)
        #expect(noNewTicks == nil)
    }
}
