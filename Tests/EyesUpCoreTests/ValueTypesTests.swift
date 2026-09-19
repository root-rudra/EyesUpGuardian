import Foundation
import Testing
@testable import EyesUpCore

@Suite struct ValueTypesTests {
    @Test func policyMapsToAssertionKinds() {
        #expect(AssertionKind.kinds(for: .system) == [.preventIdleSystemSleep])
        #expect(AssertionKind.kinds(for: [.system, .display]) == [.preventIdleSystemSleep, .preventDisplaySleep])
        #expect(AssertionKind.kinds(for: [.disk, .systemOnAC]) == [.preventDiskIdle, .preventSystemSleep])
        #expect(AssertionKind.kinds(for: []).isEmpty)
    }

    @Test func assertionKindsUseIOKitNames() {
        #expect(AssertionKind.preventDisplaySleep.ioKitType == "PreventUserIdleDisplaySleep")
        #expect(AssertionKind.preventIdleSystemSleep.ioKitType == "PreventUserIdleSystemSleep")
        #expect(AssertionKind.preventSystemSleep.ioKitType == "PreventSystemSleep")
        #expect(AssertionKind.preventDiskIdle.ioKitType == "PreventDiskIdle")
    }

    @Test func holdsRoundTripThroughJSON() throws {
        let holds = [
            makeHold(end: .indefinite),
            makeHold(end: .deadline(referenceDate.addingTimeInterval(60)), grace: 30),
            makeHold(end: .processExit(ProcessIdentity(pid: 42, startTime: 123)), source: .automation),
            makeHold(end: .triggerControlled, source: .trigger(UUID())),
        ]
        let data = try JSONEncoder().encode(holds)
        #expect(try JSONDecoder().decode([Hold].self, from: data) == holds)
    }

    @Test func effectiveDeadlineIncludesGrace() {
        let hold = makeHold(end: .deadline(referenceDate), grace: 300)
        #expect(hold.effectiveDeadline == referenceDate.addingTimeInterval(300))
        #expect(makeHold(end: .indefinite).effectiveDeadline == nil)
    }

    @Test func awakeUntilIsLatestDeadlineOnlyWhenAllHoldsHaveOne() {
        let a = makeHold(end: .deadline(referenceDate.addingTimeInterval(60)))
        let b = makeHold(end: .deadline(referenceDate.addingTimeInterval(600)))
        #expect(Hold.awakeUntil([a, b]) == referenceDate.addingTimeInterval(600))
        #expect(Hold.awakeUntil([a, makeHold(end: .indefinite)]) == nil)
        #expect(Hold.awakeUntil([]) == nil)
    }

    @Test func manualSessionCoversTimersAndIndefiniteOnly() {
        #expect(makeHold(end: .indefinite).isManualSession)
        #expect(makeHold(end: .deadline(referenceDate)).isManualSession)
        #expect(!makeHold(end: .processExit(ProcessIdentity(pid: 1, startTime: 1))).isManualSession)
        #expect(!makeHold(end: .indefinite, source: .automation).isManualSession)
        #expect(!makeHold(end: .triggerControlled, source: .trigger(UUID())).isManualSession)
    }
}
