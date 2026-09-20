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
        // Only the newly wanted metrics: CPU was sampled a moment ago and isn't due again yet.
        #expect(probes.lastRequested == [.memory, .power])
        #expect(center.snapshot.cpu != nil)

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
    @Test func refreshDoesNotSampleOnTheMainActor() {
        // resetBaselines takes the probe lock; doing that inline on the main actor lets a wake stall
        // the UI for as long as a sample takes. It has to go through the executor like sampling does.
        let executor = DeferredExecutor()
        let center = MetricsCenter(probes: probes, executor: executor, clock: clock, scheduler: scheduler)
        let subscription = center.subscribe([.network], interval: 1)
        executor.runPending()

        center.refresh()
        #expect(probes.resetCount == 0, "refresh reset baselines on the main actor")
        executor.runPending()
        #expect(probes.resetCount == 1)
        subscription.cancel()
    }
    /// Each metric keeps its own cadence. Without this, one surface asking for CPU every second
    /// drags the process table — the most expensive probe there is — to once a second with it.
    @Test func aSlowMetricIsNotPulledAlongByAFastOne() {
        let center = makeCenter()
        let fast = center.subscribe([.cpu], interval: 1)
        let slow = center.subscribe([.processes], interval: 5)
        #expect(probes.lastRequested == [.processes]) // a metric nobody was watching samples at once

        for _ in 0..<4 {
            clock.advance(1)
            scheduler.runDue(at: clock.now)
            #expect(probes.lastRequested == [.cpu], "the process list was sampled early")
        }

        clock.advance(1) // five seconds since the last process sample
        scheduler.runDue(at: clock.now)
        #expect(probes.lastRequested == [.cpu, .processes])

        fast.cancel()
        slow.cancel()
    }

    @Test func aMetricKeepsItsLastValueBetweenItsOwnSamples() {
        let center = makeCenter()
        let fast = center.subscribe([.cpu], interval: 1)
        let slow = center.subscribe([.network], interval: 5)
        #expect(center.snapshot.network != nil)

        clock.advance(1)
        scheduler.runDue(at: clock.now)
        // Network wasn't due, so it must still read what it last read — not blank out.
        #expect(center.snapshot.network != nil)
        #expect(center.snapshot.cpu != nil)

        fast.cancel()
        slow.cancel()
    }
    /// Two charts side by side must cover the same stretch of time, not the same number of samples:
    /// at 5 s a 300-sample history would be 25 minutes next to CPU's 5.
    @Test func everyMetricKeepsAboutTheSameStretchOfHistory() {
        let center = makeCenter()
        let fast = center.subscribe([.cpu], interval: 1)
        let slow = center.subscribe([.power], interval: 5)

        for tick in 1...400 {
            clock.advance(1)
            scheduler.runDue(at: clock.now)
            _ = tick
        }

        #expect(center.history(.cpu).count == 300)   // 5 minutes at 1 s
        #expect(center.history(.power).count == 60)  // 5 minutes at 5 s
        fast.cancel()
        slow.cancel()
    }
}
