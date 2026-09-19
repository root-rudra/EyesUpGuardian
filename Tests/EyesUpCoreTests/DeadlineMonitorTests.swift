import Foundation
import Testing
@testable import EyesUpCore

@Suite @MainActor struct DeadlineMonitorTests {
    let clock = FakeClock()
    let scheduler = FakeScheduler()

    func makeMonitor(lead: TimeInterval = 300) -> DeadlineMonitor {
        DeadlineMonitor(clock: clock, scheduler: scheduler, headsUpLead: lead)
    }

    @Test func armsTimerForEarliestDeadlineAndExpiresIt() {
        let monitor = makeMonitor()
        var expiredIDs: [UUID] = []
        monitor.onExpired = { expiredIDs = $0 }
        let soon = makeHold(end: .deadline(referenceDate.addingTimeInterval(60)))
        let later = makeHold(end: .deadline(referenceDate.addingTimeInterval(600)))
        monitor.update(holds: [soon, later])

        #expect(scheduler.pending.map(\.date).min() == referenceDate.addingTimeInterval(60))
        clock.advance(60)
        scheduler.runDue(at: clock.now)
        #expect(expiredIDs == [soon.id])
    }

    @Test func pastDeadlineExpiresImmediately() {
        let monitor = makeMonitor()
        var expiredIDs: [UUID] = []
        monitor.onExpired = { expiredIDs = $0 }
        clock.advance(3600) // e.g. the Mac slept through the deadline
        let hold = makeHold(end: .deadline(referenceDate.addingTimeInterval(60)))
        monitor.update(holds: [hold])
        #expect(expiredIDs == [hold.id])
    }

    @Test func graceExtendsExpiry() {
        let monitor = makeMonitor()
        monitor.update(holds: [makeHold(end: .deadline(referenceDate.addingTimeInterval(60)), grace: 120)])
        #expect(scheduler.pending.map(\.date).contains(referenceDate.addingTimeInterval(180)))
    }

    @Test func updateCancelsPreviousTimers() {
        let monitor = makeMonitor()
        monitor.update(holds: [makeHold(end: .deadline(referenceDate.addingTimeInterval(3600)))])
        let first = scheduler.entries.map(\.task)
        monitor.update(holds: [])
        #expect(first.allSatisfy { $0.isCancelled })
        #expect(scheduler.pending.isEmpty)
    }

    @Test func headsUpFiresLeadTimeBeforeTheEnd() {
        let monitor = makeMonitor(lead: 300)
        var headsUpEnd: Date?
        monitor.onHeadsUp = { headsUpEnd = $0 }
        let end = referenceDate.addingTimeInterval(3600)
        monitor.update(holds: [makeHold(end: .deadline(end))])

        clock.advance(3300)
        scheduler.runDue(at: clock.now)
        #expect(headsUpEnd == end)
    }

    @Test func noHeadsUpWhenAnotherHoldHasNoEnd() {
        let monitor = makeMonitor()
        monitor.update(holds: [makeHold(end: .deadline(referenceDate.addingTimeInterval(3600))), makeHold(end: .indefinite)])
        #expect(!scheduler.pending.map(\.date).contains(referenceDate.addingTimeInterval(3300)))
    }

    @Test func noHeadsUpWhenLessThanLeadRemains() {
        let monitor = makeMonitor(lead: 300)
        monitor.update(holds: [makeHold(end: .deadline(referenceDate.addingTimeInterval(120)))])
        #expect(scheduler.pending.count == 1) // only the expiry timer
    }

    @Test func sameEndIsNotAnnouncedTwiceButAnExtendedEndIs() {
        let monitor = makeMonitor(lead: 300)
        var count = 0
        monitor.onHeadsUp = { _ in count += 1 }
        let hold = makeHold(end: .deadline(referenceDate.addingTimeInterval(3600)))
        monitor.update(holds: [hold])
        clock.advance(3300)
        scheduler.runDue(at: clock.now)
        monitor.update(holds: [hold])
        scheduler.runDue(at: clock.now)
        #expect(count == 1)

        var extended = hold
        extended.end = .deadline(referenceDate.addingTimeInterval(7200))
        monitor.update(holds: [extended])
        clock.advance(3600)
        scheduler.runDue(at: clock.now)
        #expect(count == 2)
    }
}
