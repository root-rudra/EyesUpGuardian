import Foundation
import Testing
@testable import EyesUpCore

@Suite @MainActor struct AwakeControllerTests {
    let provider = FakePowerAssertions()
    let clock = FakeClock()
    let scheduler = FakeScheduler()
    let watcher = FakeExitWatcher()
    let inspector = FakeInspector()
    let ownPID: Int32 = 777

    func makeController(store: JSONFileStore<[Hold]>? = nil) -> AwakeController {
        AwakeController(
            provider: provider, clock: clock, scheduler: scheduler, exitWatcher: watcher,
            inspector: inspector, holdStore: store, headsUpLead: 300, ownPID: ownPID
        )
    }

    func tempStore() -> JSONFileStore<[Hold]> {
        JSONFileStore(
            url: FileManager.default.temporaryDirectory.appendingPathComponent("EyesUpTests-\(UUID().uuidString)/holds.json"),
            schemaVersion: 1
        )
    }

    // MARK: Timers and sessions

    @Test func startTimerKeepsMacAwakeUntilDeadline() throws {
        let controller = makeController()
        let hold = try controller.startTimer(duration: 7200, policy: .system)
        #expect(hold.label == "Timer 2h")
        #expect(controller.awakeUntil == referenceDate.addingTimeInterval(7200))
        #expect(provider.liveNames == ["EyesUpGuardian: Timer 2h"])

        clock.advance(7200)
        scheduler.runDue(at: clock.now)
        #expect(controller.holds.isEmpty)
        #expect(provider.live.isEmpty)
    }

    @Test(arguments: [0.0, -5.0, AwakeController.maxManualDuration + 1])
    func startTimerRejectsBadDurations(seconds: Double) {
        let controller = makeController()
        #expect(throws: AwakeError.invalidDuration) { try controller.startTimer(duration: seconds, policy: .system) }
        #expect(controller.holds.isEmpty)
    }

    @Test func newManualSessionReplacesThePreviousOne() throws {
        let controller = makeController()
        try controller.startTimer(duration: 3600, policy: .system)
        try controller.startTimer(duration: 7200, policy: .system)
        #expect(controller.holds.map(\.label) == ["Timer 2h"])
        controller.startIndefinite(policy: .system)
        #expect(controller.holds.map(\.label) == ["Indefinitely"])
        #expect(controller.awakeUntil == nil)
    }

    @Test func startUntilRejectsPastTimes() {
        let controller = makeController()
        #expect(throws: AwakeError.dateInPast) { try controller.startUntil(referenceDate.addingTimeInterval(-60), policy: .system) }
        #expect(throws: AwakeError.dateInPast) { try controller.startUntil(referenceDate, policy: .system) }
    }

    @Test func startUntilLabelsWithTheTime() throws {
        let controller = makeController()
        let hold = try controller.startUntil(referenceDate.addingTimeInterval(3600), policy: .system)
        #expect(hold.label.hasPrefix("Until "))
        #expect(controller.awakeUntil == referenceDate.addingTimeInterval(3600))
    }

    @Test func extendAddsTimeToTimers() throws {
        let controller = makeController()
        try controller.startTimer(duration: 3600, policy: .system)
        try controller.extend(by: 1800, policy: .system)
        #expect(controller.awakeUntil == referenceDate.addingTimeInterval(5400))
        #expect(controller.holds.first?.label.hasPrefix("Until ") == true)
    }

    @Test func extendWithNoTimerStartsOne() throws {
        let controller = makeController()
        try controller.extend(by: 1800, policy: .system)
        #expect(controller.holds.map(\.label) == ["Timer 30m"])
    }

    // MARK: Processes

    @Test func watchProcessHoldsUntilExit() throws {
        let identity = ProcessIdentity(pid: 4242, startTime: 5)
        inspector.identities[4242] = identity
        inspector.names[4242] = "swift-build"
        let controller = makeController()

        let hold = try controller.watchProcess(pid: 4242, policy: .system)
        #expect(hold.label == "PID 4242 · swift-build")
        #expect(watcher.watched[identity] != nil)

        watcher.simulateExit(identity)
        #expect(controller.holds.isEmpty)
        #expect(provider.live.isEmpty)
    }

    @Test func processGraceKeepsMacAwakeAfterExit() throws {
        let identity = ProcessIdentity(pid: 4242, startTime: 5)
        inspector.identities[4242] = identity
        let controller = makeController()
        try controller.watchProcess(pid: 4242, policy: .system, grace: 300)

        watcher.simulateExit(identity)
        #expect(controller.awakeUntil == referenceDate.addingTimeInterval(300))
        clock.advance(300)
        scheduler.runDue(at: clock.now)
        #expect(controller.holds.isEmpty)
    }

    @Test func watchProcessRejectsMissingProcess() {
        let controller = makeController()
        #expect(throws: AwakeError.noSuchProcess) { try controller.watchProcess(pid: 4242, policy: .system) }
    }

    @Test func watchProcessRejectsOwnAndInvalidPIDs() {
        let controller = makeController()
        #expect(throws: AwakeError.ownProcess) { try controller.watchProcess(pid: ownPID, policy: .system) }
        #expect(throws: AwakeError.invalidPID) { try controller.watchProcess(pid: 0, policy: .system) }
        #expect(throws: AwakeError.invalidPID) { try controller.watchProcess(pid: -3, policy: .system) }
    }

    @Test(arguments: ["", "abc", "-5", "0", "99999999999", "12 34", "٣", "12a", "+12", "1e3"])
    func parsePIDRejectsGarbage(text: String) {
        #expect(throws: AwakeError.invalidPID) { try AwakeController.parsePID(text) }
    }

    @Test func parsePIDAcceptsDigitsWithSurroundingSpaces() throws {
        #expect(try AwakeController.parsePID(" 4242 ") == 4242)
    }

    @Test func stoppingAProcessHoldCancelsItsWatch() throws {
        let identity = ProcessIdentity(pid: 4242, startTime: 5)
        inspector.identities[4242] = identity
        let controller = makeController()
        let hold = try controller.watchProcess(pid: 4242, policy: .system)
        controller.stop(id: hold.id)
        #expect(watcher.watched.isEmpty)
    }

    // MARK: Overlaps, display, nudge

    @Test func stoppingOneOverlappingHoldKeepsMacAwake() throws {
        let identity = ProcessIdentity(pid: 4242, startTime: 5)
        inspector.identities[4242] = identity
        let controller = makeController()
        let timer = try controller.startTimer(duration: 3600, policy: .system)
        try controller.watchProcess(pid: 4242, policy: .system)

        controller.stop(id: timer.id)
        #expect(provider.liveKinds == [.preventIdleSystemSleep])

        controller.stopAll()
        #expect(controller.holds.isEmpty)
        #expect(provider.live.isEmpty)
    }

    @Test func displayToggleAddsAndRemovesDisplayAssertion() throws {
        let controller = makeController()
        try controller.startTimer(duration: 3600, policy: .system)
        controller.setDisplayOn(true)
        #expect(controller.displayOn)
        #expect(provider.liveKinds == [.preventIdleSystemSleep, .preventDisplaySleep])
        controller.setDisplayOn(false)
        #expect(provider.liveKinds == [.preventIdleSystemSleep])
    }

    @Test func nudgeDeclaresUserActivity() {
        let controller = makeController()
        controller.nudgeDisplay()
        #expect(provider.userActivityCount == 1)
    }

    @Test func assertionFailureIsSurfaced() throws {
        provider.failingKinds = [.preventIdleSystemSleep]
        let controller = makeController()
        try controller.startTimer(duration: 60, policy: .system)
        #expect(controller.lastError?.kind == .preventIdleSystemSleep)
    }

    // MARK: Heads-up

    @Test func headsUpHandlerIsCalledBeforeTheEnd() throws {
        let controller = makeController()
        var announced: Date?
        controller.setHeadsUpHandler { announced = $0 }
        try controller.startTimer(duration: 3600, policy: .system)
        clock.advance(3300)
        scheduler.runDue(at: clock.now)
        #expect(announced == referenceDate.addingTimeInterval(3600))
    }

    // MARK: Persistence

    @Test func holdsSurviveARestart() throws {
        let store = tempStore()
        let first = makeController(store: store)
        first.startIndefinite(policy: .system)

        let second = makeController(store: store)
        second.restore()
        #expect(second.holds.map(\.label) == ["Indefinitely"])
        #expect(second.isAwake)
    }

    @Test func restoreReportsCorruptStore() throws {
        let store = tempStore()
        try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("garbage".utf8).write(to: store.url)
        let controller = makeController(store: store)
        controller.restore()
        #expect(controller.holds.isEmpty)
        #expect(controller.storeNotice != nil)
    }

    @Test func restoreDropsOutOfRangeHoldsAndReportsIt() throws {
        let store = tempStore()
        try store.save([makeHold(end: .deadline(Date(timeIntervalSinceReferenceDate: 1e300)))])
        let controller = makeController(store: store)
        controller.restore()
        #expect(controller.holds.isEmpty)
        #expect(provider.live.isEmpty)
        #expect(controller.storeNotice != nil)
    }

    @Test func shutdownStopsEverythingAndSavesEmpty() throws {
        let store = tempStore()
        let controller = makeController(store: store)
        controller.startIndefinite(policy: .system)
        controller.shutdown()
        #expect(provider.live.isEmpty)
        guard case .loaded(let saved) = store.load() else { Issue.record("expected saved file"); return }
        #expect(saved.isEmpty)
    }

    // MARK: Trigger holds

    @Test func triggerHoldIsNotAManualSessionAndHasNoEnd() {
        let controller = makeController()
        let triggerID = UUID()
        controller.beginTriggerHold(triggerID: triggerID, label: "Claude running", policy: .system)
        #expect(controller.isAwake)
        #expect(controller.awakeUntil == nil)
        #expect(provider.liveNames == ["EyesUpGuardian: Claude running"])

        _ = try? controller.startTimer(duration: 3600, policy: .system)
        #expect(controller.holds.count == 2)
        #expect(controller.hasTriggerHold(triggerID: triggerID))
    }

    @Test func beginningTheSameTriggerTwiceKeepsOneHold() {
        let controller = makeController()
        let triggerID = UUID()
        controller.beginTriggerHold(triggerID: triggerID, label: "A", policy: .system)
        controller.beginTriggerHold(triggerID: triggerID, label: "B", policy: [.system, .display])
        #expect(controller.holds.count == 1)
        #expect(controller.holds.first?.label == "B")
        #expect(provider.liveKinds == [.preventIdleSystemSleep, .preventDisplaySleep])
    }

    @Test func endingATriggerHoldRespectsGrace() {
        let controller = makeController()
        let triggerID = UUID()
        controller.beginTriggerHold(triggerID: triggerID, label: "Build", policy: .system)
        controller.endTriggerHold(triggerID: triggerID, grace: 300)
        #expect(controller.awakeUntil == referenceDate.addingTimeInterval(300))

        clock.advance(300)
        scheduler.runDue(at: clock.now)
        #expect(controller.holds.isEmpty)
        #expect(provider.live.isEmpty)
    }

    @Test func conditionReturningDuringGraceCancelsTheCountdown() {
        let controller = makeController()
        let triggerID = UUID()
        controller.beginTriggerHold(triggerID: triggerID, label: "Build", policy: .system)
        controller.endTriggerHold(triggerID: triggerID, grace: 300)
        controller.beginTriggerHold(triggerID: triggerID, label: "Build", policy: .system)
        #expect(controller.holds.count == 1)
        #expect(controller.awakeUntil == nil)

        clock.advance(600)
        scheduler.runDue(at: clock.now)
        #expect(controller.isAwake)
    }

    @Test func stopAllLeavesTriggerHoldsButRemoveTriggerHoldsClearsThem() {
        let controller = makeController()
        let triggerID = UUID()
        controller.beginTriggerHold(triggerID: triggerID, label: "Claude running", policy: .system)
        _ = try? controller.startTimer(duration: 3600, policy: .system)

        controller.stopAll()
        #expect(controller.holds.map(\.label) == ["Claude running"])

        controller.removeTriggerHolds()
        #expect(controller.holds.isEmpty)
        #expect(provider.live.isEmpty)
    }

    // MARK: Safety cap and emergency release

    @Test func safetyCapEndsAnIndefiniteHoldAndReportsIt() {
        let controller = makeController()
        var released: [String] = []
        controller.onSafetyRelease = { released = $0 }
        controller.setSafetyCap(3600)
        controller.startIndefinite(policy: .system)
        #expect(controller.awakeUntil == referenceDate.addingTimeInterval(3600))

        clock.advance(3600)
        scheduler.runDue(at: clock.now)
        #expect(controller.holds.isEmpty)
        #expect(released == ["Indefinitely"])
        #expect(provider.live.isEmpty)
    }

    @Test func normalExpiryIsNotReportedAsASafetyRelease() throws {
        let controller = makeController()
        var released: [String] = []
        controller.onSafetyRelease = { released = $0 }
        controller.setSafetyCap(3600)
        try controller.startTimer(duration: 1800, policy: .system)

        clock.advance(1800)
        scheduler.runDue(at: clock.now)
        #expect(controller.holds.isEmpty)
        #expect(released.isEmpty)
    }

    @Test func clearingTheSafetyCapRestoresNoEndTime() {
        let controller = makeController()
        controller.setSafetyCap(3600)
        controller.startIndefinite(policy: .system)
        controller.setSafetyCap(nil)
        #expect(controller.awakeUntil == nil)
        clock.advance(7200)
        scheduler.runDue(at: clock.now)
        #expect(controller.isAwake)
    }

    @Test func releaseAllForSafetyDropsEverythingIncludingTriggers() {
        let controller = makeController()
        controller.beginTriggerHold(triggerID: UUID(), label: "Claude running", policy: .system)
        controller.startIndefinite(policy: .system)
        controller.releaseAllForSafety()
        #expect(controller.holds.isEmpty)
        #expect(provider.live.isEmpty)
    }

    // MARK: Automation

    @Test func automationStartCreatesItsOwnHold() throws {
        let controller = makeController()
        _ = try controller.apply(.start(duration: .finite(3600), display: true))
        #expect(controller.holds.count == 1)
        #expect(controller.holds.first?.source == .automation)
        #expect(provider.liveKinds == [.preventIdleSystemSleep, .preventDisplaySleep])

        _ = try controller.apply(.start(duration: .finite(1800), display: false))
        #expect(controller.holds.count == 1) // replaces its previous session
        #expect(controller.awakeUntil == referenceDate.addingTimeInterval(1800))
    }

    @Test func stopOnlyEndsAutomationHolds() throws {
        let controller = makeController()
        try controller.startTimer(duration: 3600, policy: .system)
        _ = try controller.apply(.start(duration: .infinite, display: false))
        _ = try controller.apply(.stop)
        #expect(controller.holds.map(\.source) == [.manual])
        #expect(controller.isAwake)
    }

    @Test func automationExtendAddsToItsOwnHoldOrStartsOne() throws {
        let controller = makeController()
        _ = try controller.apply(.start(duration: .finite(3600), display: false))
        _ = try controller.apply(.extend(by: 1800))
        #expect(controller.awakeUntil == referenceDate.addingTimeInterval(5400))

        let fresh = makeController()
        _ = try fresh.apply(.extend(by: 1800))
        #expect(fresh.holds.count == 1)
        #expect(fresh.holds.first?.source == .automation)
    }

    @Test func automationExtendCannotCompoundPastItsCap() throws {
        let controller = makeController()
        _ = try controller.apply(.start(duration: .finite(7200), display: false))
        for _ in 0..<5 { _ = try controller.apply(.extend(by: 24 * 3600)) }
        #expect(controller.awakeUntil == referenceDate.addingTimeInterval(AutomationParser.maxDuration))
    }

    @Test func automationRespectsALowerSafetyCap() throws {
        let controller = makeController()
        controller.setSafetyCap(3600)
        _ = try controller.apply(.start(duration: .finite(1800), display: false))
        _ = try controller.apply(.extend(by: 24 * 3600))
        #expect(controller.awakeUntil == referenceDate.addingTimeInterval(3600))
    }

    @Test func automationRejectsAbsurdDurations() {
        let controller = makeController()
        #expect(throws: AwakeError.invalidDuration) { try controller.apply(.extend(by: 0)) }
        #expect(throws: AwakeError.invalidDuration) { try controller.apply(.start(duration: .finite(1e12), display: false)) }
    }

    @Test func manyHoldsWatchingOnePIDArmOneWatch() throws {
        let identity = ProcessIdentity(pid: 4242, startTime: 5)
        inspector.identities[4242] = identity
        let store = tempStore()
        try store.save((0..<20).map {
            makeHold(label: "Watch \($0)", end: .processExit(identity), createdAt: referenceDate)
        })
        let controller = makeController(store: store)
        controller.restore()
        #expect(controller.holds.count == 20)
        #expect(watcher.watched.count == 1) // one process, one kqueue source

        watcher.simulateExit(identity)
        #expect(controller.holds.isEmpty) // all of them end together, in one pass
    }

    @Test func automationStartClampsItsOwnDurationEvenIfAskedForMore() throws {
        let controller = makeController()
        _ = try controller.apply(.start(duration: .finite(999 * 3600), display: false))
        #expect(controller.awakeUntil == referenceDate.addingTimeInterval(AutomationParser.maxDuration))

        _ = try controller.apply(.start(duration: .infinite, display: false))
        #expect(controller.awakeUntil == referenceDate.addingTimeInterval(AutomationParser.maxDuration))
    }

    @Test func manualExtendLeavesAutomationHoldsAlone() throws {
        let controller = makeController()
        _ = try controller.apply(.start(duration: .finite(3600), display: false))
        try controller.extend(by: 24 * 3600, policy: .system)
        // The link's session keeps its own end; the manual extend started a manual timer instead.
        #expect(controller.holds.filter { $0.source == .automation }.count == 1)
        #expect(controller.holds.contains { $0.source == .manual })
        #expect(controller.awakeUntil == referenceDate.addingTimeInterval(24 * 3600))
    }
    @Test func parsePIDAcceptsAPastedValueWithANewline() throws {
        #expect(try AwakeController.parsePID("48213\n") == 48213)
        #expect(try AwakeController.parsePID(" 48213 \n") == 48213)
    }
    /// PID 1 is launchd: it always exists and always belongs to root, so libproc refuses its
    /// identity. Saying "no such process" there would be a lie.
    @Test func watchingAnotherUsersProcessSaysSo() {
        let controller = makeController()
        #expect(throws: AwakeError.notYourProcess) { try controller.watchProcess(pid: 1, policy: .system) }
    }

    @Test func watchingAPIDThatDoesNotExistStillSaysThat() {
        let controller = makeController()
        #expect(throws: AwakeError.noSuchProcess) {
            try controller.watchProcess(pid: Int32.max - 1, policy: .system)
        }
    }
    /// Regression: "+30m" used to fall through to startTimer, which replaces the manual session —
    /// an indefinite session would be cut down to 30 minutes.
    @Test func extendingAnIndefiniteSessionNeverShortensIt() {
        let controller = makeController()
        let started = controller.startIndefinite(policy: .system)
        #expect(throws: AwakeError.sessionHasNoEnd) { try controller.extend(by: 1800, policy: .system) }
        #expect(controller.holds.count == 1)
        #expect(controller.holds.first?.id == started.id)
        #expect(controller.holds.first?.end == .indefinite)
    }

    @Test func extendingWithNothingRunningStillStartsATimer() throws {
        let controller = makeController()
        try controller.extend(by: 1800, policy: .system)
        #expect(controller.holds.count == 1)
        #expect(controller.awakeUntil == clock.now.addingTimeInterval(1800))
    }
    @Test func watchingTheSamePIDTwiceKeepsOneHold() throws {
        let identity = ProcessIdentity(pid: 4242, startTime: 99)
        inspector.identities[4242] = identity
        let controller = makeController()
        let first = try controller.watchProcess(pid: 4242, policy: .system)
        let second = try controller.watchProcess(pid: 4242, policy: [.system, .display])

        #expect(controller.holds.count == 1)
        #expect(first.id == second.id)
        #expect(controller.holds.first?.policy == [.system, .display])
    }
}
