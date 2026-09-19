import Foundation
import Testing
@testable import EyesUpCore

@Suite @MainActor struct PollingMonitorTests {
    let clock = FakeClock()
    let scheduler = FakeScheduler()

    @Test func processMonitorPollsAndMatchesCaseInsensitively() {
        let lister = FakeProcessLister()
        lister.names = ["Finder"]
        let monitor = ProcessRunningMonitor(names: ["node", "Claude"], lister: lister, clock: clock, scheduler: scheduler)
        var answers: [Bool] = []
        monitor.start { answers.append($0) }
        #expect(answers == [false])

        lister.names = ["Finder", "claude"]
        clock.advance(ProcessRunningMonitor.interval)
        scheduler.runDue(at: clock.now)
        #expect(answers == [false, true])

        lister.names = ["Finder"]
        clock.advance(ProcessRunningMonitor.interval)
        scheduler.runDue(at: clock.now)
        #expect(answers == [false, true, false])
    }

    @Test func processMonitorStopsPolling() {
        let lister = FakeProcessLister()
        let monitor = ProcessRunningMonitor(names: ["node"], lister: lister, clock: clock, scheduler: scheduler)
        monitor.start { _ in }
        monitor.stop()
        #expect(scheduler.pending.isEmpty)
    }

    @Test func cpuActivityMonitorNeedsSustainedLoad() {
        let counters = FakeCounters()
        counters.cpu = (busy: 0, total: 1000)
        let monitor = ActivityMonitor(
            kind: .cpu, threshold: ActivityThreshold(value: 40, sustain: 30, release: 30),
            counters: counters, clock: clock, scheduler: scheduler
        )
        var answers: [Bool] = []
        monitor.start { answers.append($0) }
        #expect(answers == [false]) // no baseline yet

        // Each tick: 90 busy ticks out of 100 = 90%.
        for step in 1...3 {
            counters.cpu = (busy: UInt64(90 * step), total: UInt64(1000 + 100 * step))
            clock.advance(ActivityMonitor.interval)
            scheduler.runDue(at: clock.now)
        }
        #expect(answers.last == true)
        #expect(answers.filter { $0 }.count == 1) // reported once, not on every poll
    }

    @Test func networkActivityMonitorUsesByteRate() {
        let counters = FakeCounters()
        counters.network = 0
        let monitor = ActivityMonitor(
            kind: .network, threshold: ActivityThreshold(value: 1_000_000, sustain: 0, release: 0),
            counters: counters, clock: clock, scheduler: scheduler
        )
        var answers: [Bool] = []
        monitor.start { answers.append($0) }

        counters.network = 30_000_000 // 2 MB/s over 15 s
        clock.advance(ActivityMonitor.interval)
        scheduler.runDue(at: clock.now)
        #expect(answers.last == true)

        counters.network = 30_100_000 // ~7 KB/s
        clock.advance(ActivityMonitor.interval)
        scheduler.runDue(at: clock.now)
        #expect(answers.last == false)
    }

    @Test func diskActivityMonitorReadsWrites() {
        let counters = FakeCounters()
        counters.disk = 0
        let monitor = ActivityMonitor(
            kind: .disk, threshold: ActivityThreshold(value: 20_000_000, sustain: 0, release: 0),
            counters: counters, clock: clock, scheduler: scheduler
        )
        var answers: [Bool] = []
        monitor.start { answers.append($0) }

        counters.disk = 600_000_000 // 40 MB/s over 15 s
        clock.advance(ActivityMonitor.interval)
        scheduler.runDue(at: clock.now)
        #expect(answers.last == true)
    }

    @Test func missingCountersNeverReportBusy() {
        let counters = FakeCounters() // every reading nil
        let monitor = ActivityMonitor(
            kind: .cpu, threshold: ActivityThreshold(value: 1, sustain: 0, release: 0),
            counters: counters, clock: clock, scheduler: scheduler
        )
        var answers: [Bool] = []
        monitor.start { answers.append($0) }
        clock.advance(ActivityMonitor.interval)
        scheduler.runDue(at: clock.now)
        #expect(answers == [false])
    }

    @Test func reevaluateStartsAFreshBaselineAfterSleep() {
        let counters = FakeCounters()
        counters.network = 0
        let monitor = ActivityMonitor(
            kind: .network, threshold: ActivityThreshold(value: 1000, sustain: 0, release: 0),
            counters: counters, clock: clock, scheduler: scheduler
        )
        var answers: [Bool] = []
        monitor.start { answers.append($0) }

        // The Mac slept for an hour; the counter jumped, but that isn't a rate.
        counters.network = 500_000_000
        clock.advance(3600)
        monitor.reevaluate()
        scheduler.runDue(at: clock.now)
        #expect(answers.last == false)
    }
}
