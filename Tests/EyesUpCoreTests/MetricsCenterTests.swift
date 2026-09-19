import Foundation
import Testing
@testable import EyesUpCore

@Suite @MainActor struct MetricsCenterTests {
    let clock = FakeClock()
    let scheduler = FakeScheduler()
    let probes = FakeProbes()

    func makeCenter() -> MetricsCenter {
        MetricsCenter(probes: probes, executor: InlineExecutor(), clock: clock, scheduler: scheduler)
    }

    @Test func noTimerWhenNothingIsSubscribed() {
        let center = makeCenter()
        #expect(!center.isSampling)
        #expect(scheduler.pending.isEmpty)
        #expect(probes.sampleCount == 0)
    }

    @Test func subscribingSamplesAtOnceAndThenOnItsInterval() {
        let center = makeCenter()
        let subscription = center.subscribe([.cpu], interval: 1)
        #expect(probes.sampleCount == 1)
        #expect(center.snapshot.cpu?.total == 25)

        clock.advance(1)
        scheduler.runDue(at: clock.now)
        #expect(probes.sampleCount == 2)
        subscription.cancel()
    }

    @Test func samplesOnlyTheUnionOfSubscribedMetrics() {
        let center = makeCenter()
        let first = center.subscribe([.cpu], interval: 1)
        let second = center.subscribe([.memory, .power], interval: 5)
        #expect(probes.lastRequested == [.cpu, .memory, .power])

        second.cancel()
        clock.advance(1)
        scheduler.runDue(at: clock.now)
        #expect(probes.lastRequested == [.cpu])
        first.cancel()
    }

    @Test func theFastestIntervalWins() {
        let center = makeCenter()
        let slow = center.subscribe([.cpu], interval: 10)
        let fast = center.subscribe([.memory], interval: 1)
        #expect(scheduler.pending.map(\.date).min() == referenceDate.addingTimeInterval(1))
        // Cancelling the fast subscriber re-arms from now at the slow interval.
        fast.cancel()
        #expect(scheduler.pending.map(\.date).min() == referenceDate.addingTimeInterval(10))
        clock.advance(10)
        scheduler.runDue(at: clock.now)
        #expect(scheduler.pending.map(\.date).min() == referenceDate.addingTimeInterval(20))
        slow.cancel()
    }

    @Test func stopsSamplingWhenTheLastSubscriberGoesAway() {
        let center = makeCenter()
        let subscription = center.subscribe([.cpu], interval: 1)
        subscription.cancel()
        #expect(!center.isSampling)
        #expect(scheduler.pending.isEmpty)

        let countAfterCancel = probes.sampleCount
        clock.advance(60)
        scheduler.runDue(at: clock.now)
        #expect(probes.sampleCount == countAfterCancel)
    }

    @Test func historyKeepsTheLastValuesAndNoMore() {
        let center = makeCenter()
        let subscription = center.subscribe([.cpu], interval: 1)
        for step in 1...(MetricsCenter.historyLength + 20) {
            probes.cpuTotal = Double(step % 100)
            clock.advance(1)
            scheduler.runDue(at: clock.now)
        }
        #expect(center.history(.cpu).count == MetricsCenter.historyLength)
        #expect(center.history(.cpu).last == center.snapshot.cpu?.total)
        #expect(center.history(.memory).isEmpty)
        subscription.cancel()
    }

    @Test func aFailingProbeLeavesOtherMetricsIntact() {
        let center = makeCenter()
        let subscription = center.subscribe([.cpu, .power], interval: 1)
        #expect(center.snapshot.power?.watts == 40)

        probes.powerAvailable = false
        clock.advance(1)
        scheduler.runDue(at: clock.now)
        #expect(center.snapshot.power == nil)     // the stat blanks
        #expect(center.snapshot.cpu != nil)       // its neighbours keep working
        subscription.cancel()
    }

    @Test func refreshDropsStaleBaselines() {
        let center = makeCenter()
        let subscription = center.subscribe([.network], interval: 1)
        center.refresh()
        #expect(probes.resetCount == 1)
        #expect(probes.sampleCount == 2) // refresh re-samples immediately
        subscription.cancel()
    }
}
