import Foundation
import Testing
@testable import EyesUpCore

@Suite @MainActor struct TriggerEngineTests {
    let provider = FakePowerAssertions()
    let clock = FakeClock()
    let scheduler = FakeScheduler()
    let factory = FakeMonitorFactory()

    func makeController() -> AwakeController {
        AwakeController(provider: provider, clock: clock, scheduler: scheduler,
                        exitWatcher: FakeExitWatcher(), inspector: FakeInspector(), holdStore: nil)
    }

    func makeEngine(controller: AwakeController, store: JSONFileStore<[Trigger]>? = nil) -> TriggerEngine {
        TriggerEngine(controller: controller, factory: factory, clock: clock, scheduler: scheduler, store: store)
    }

    func tempStore() -> JSONFileStore<[Trigger]> {
        JSONFileStore(
            url: FileManager.default.temporaryDirectory.appendingPathComponent("EyesUpTests-\(UUID().uuidString)/triggers.json"),
            schemaVersion: 1
        )
    }

    @Test func aTrueConditionTakesAHold() throws {
        let controller = makeController()
        let engine = makeEngine(controller: controller)
        let trigger = makeTrigger(name: "Claude running")
        try engine.add(trigger)

        factory.last?.send(true)
        #expect(controller.hasTriggerHold(triggerID: trigger.id))
        #expect(provider.liveNames == ["EyesUpGuardian: Claude running"])
    }

    @Test func repeatedReportsDoNotDuplicateHolds() throws {
        let controller = makeController()
        let engine = makeEngine(controller: controller)
        try engine.add(makeTrigger())
        factory.last?.send(true)
        factory.last?.send(true)
        factory.last?.send(true)
        #expect(controller.holds.count == 1)
        #expect(provider.createCount == 1)
    }

    @Test func aFalseConditionReleasesAfterGrace() throws {
        let controller = makeController()
        let engine = makeEngine(controller: controller)
        try engine.add(makeTrigger(grace: 300))
        factory.last?.send(true)
        factory.last?.send(false)
        #expect(controller.isAwake)

        clock.advance(300)
        scheduler.runDue(at: clock.now)
        #expect(controller.holds.isEmpty)
    }

    @Test func conditionReturningDuringGraceKeepsOneHold() throws {
        let controller = makeController()
        let engine = makeEngine(controller: controller)
        try engine.add(makeTrigger(grace: 300))
        factory.last?.send(true)
        factory.last?.send(false)
        factory.last?.send(true)
        clock.advance(600)
        scheduler.runDue(at: clock.now)
        #expect(controller.holds.count == 1)
    }

    @Test func disablingATriggerStopsItsMonitorAndDropsItsHold() throws {
        let controller = makeController()
        let engine = makeEngine(controller: controller)
        let trigger = makeTrigger(grace: 300)
        try engine.add(trigger)
        factory.last?.send(true)

        engine.setEnabled(false, id: trigger.id)
        #expect(controller.holds.isEmpty)
        #expect(factory.last?.isStarted == false)
        #expect(engine.triggers.first?.isEnabled == false)
    }

    @Test func aDisabledTriggerNeverStartsAMonitor() throws {
        let engine = makeEngine(controller: makeController())
        try engine.add(makeTrigger(isEnabled: false))
        #expect(factory.made.isEmpty)
    }

    @Test func removingATriggerDropsItsHold() throws {
        let controller = makeController()
        let engine = makeEngine(controller: controller)
        let trigger = makeTrigger()
        try engine.add(trigger)
        factory.last?.send(true)

        engine.remove(id: trigger.id)
        #expect(controller.holds.isEmpty)
        #expect(engine.triggers.isEmpty)
    }

    @Test func updatingATriggerRestartsItsMonitor() throws {
        let controller = makeController()
        let engine = makeEngine(controller: controller)
        var trigger = makeTrigger(condition: .onACPower)
        try engine.add(trigger)
        factory.last?.send(true)

        trigger.condition = .processRunning(names: ["node"])
        try engine.update(trigger)
        #expect(controller.holds.isEmpty)          // the old hold went with the old condition
        #expect(factory.made.count == 2)
        #expect(factory.made.first?.isStarted == false)
        if case .processRunning = factory.last?.condition {} else { Issue.record("monitor not rebuilt") }
    }

    @Test func invalidTriggersAreRejected() {
        let engine = makeEngine(controller: makeController())
        #expect(throws: TriggerError.invalid) { try engine.add(makeTrigger(name: " ")) }
        #expect(engine.triggers.isEmpty)
    }

    @Test func pauseDropsHoldsAndIgnoresReports() throws {
        let controller = makeController()
        let engine = makeEngine(controller: controller)
        try engine.add(makeTrigger())
        factory.last?.send(true)

        engine.setPause(.untilResumed)
        #expect(controller.holds.isEmpty)
        factory.last?.send(false)
        factory.last?.send(true)
        #expect(controller.holds.isEmpty)
    }

    @Test func resumeReappliesStillTrueConditions() throws {
        let controller = makeController()
        let engine = makeEngine(controller: controller)
        try engine.add(makeTrigger())
        factory.last?.send(true)
        engine.setPause(.untilResumed)
        engine.setPause(.none)
        #expect(controller.holds.count == 1)
    }

    @Test func aTimedPauseResumesOnSchedule() throws {
        let controller = makeController()
        let engine = makeEngine(controller: controller)
        try engine.add(makeTrigger())
        factory.last?.send(true)

        engine.setPause(.until(referenceDate.addingTimeInterval(3600)))
        #expect(controller.holds.isEmpty)
        clock.advance(3600)
        scheduler.runDue(at: clock.now)
        #expect(engine.pause == .none)
        #expect(controller.holds.count == 1)
    }

    @Test func refreshResumesAPauseThatExpiredWhileAsleep() throws {
        let controller = makeController()
        let engine = makeEngine(controller: controller)
        try engine.add(makeTrigger())
        factory.last?.send(true)
        engine.setPause(.until(referenceDate.addingTimeInterval(3600)))

        clock.advance(7200) // the Mac slept through the resume time
        engine.refresh()
        #expect(engine.pause == .none)
        #expect(controller.holds.count == 1)
        #expect(factory.last?.reevaluateCount == 1)
    }

    @Test func notifyOnChangeReportsBothEdges() throws {
        let engine = makeEngine(controller: makeController())
        var messages: [String] = []
        engine.onNotify = { messages.append($0) }
        try engine.add(makeTrigger(name: "Claude running", notifyOnChange: true))
        factory.last?.send(true)
        factory.last?.send(false)
        #expect(messages.count == 2)
        #expect(messages.allSatisfy { $0.contains("Claude running") })
    }

    @Test func loadDropsInvalidTriggersWithNotice() throws {
        let store = tempStore()
        try store.save([makeTrigger(name: "Good"), makeTrigger(name: " "), makeTrigger(grace: 99_999)])
        let engine = makeEngine(controller: makeController(), store: store)
        engine.load()
        #expect(engine.triggers.map(\.name) == ["Good"])
        #expect(engine.storeNotice != nil)
        #expect(factory.made.count == 1)
    }

    @Test func loadReportsCorruptStore() throws {
        let store = tempStore()
        try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("nonsense".utf8).write(to: store.url)
        let engine = makeEngine(controller: makeController(), store: store)
        engine.load()
        #expect(engine.triggers.isEmpty)
        #expect(engine.storeNotice != nil)
    }

    @Test func triggersSurviveARestart() throws {
        let store = tempStore()
        let first = makeEngine(controller: makeController(), store: store)
        try first.add(makeTrigger(name: "Claude running"))

        let second = TriggerEngine(controller: makeController(), factory: FakeMonitorFactory(),
                                   clock: clock, scheduler: scheduler, store: store)
        second.load()
        #expect(second.triggers.map(\.name) == ["Claude running"])
    }

    @Test func shutdownStopsMonitorsAndLeavesHoldsToTheController() throws {
        let controller = makeController()
        let engine = makeEngine(controller: controller)
        try engine.add(makeTrigger())
        factory.last?.send(true)
        engine.shutdown()
        #expect(factory.last?.isStarted == false)
    }

    @Test func loadCapsTheNumberOfTriggers() throws {
        let store = tempStore()
        try store.save((0..<(TriggerValidator.maxTriggers + 20)).map { makeTrigger(name: "Trigger \($0)") })
        let engine = makeEngine(controller: makeController(), store: store)
        engine.load()
        #expect(engine.triggers.count == TriggerValidator.maxTriggers)
        #expect(engine.storeNotice != nil)
        #expect(factory.made.count == TriggerValidator.maxTriggers)
    }

    @Test func addRefusesToGoOverTheLimit() throws {
        let engine = makeEngine(controller: makeController())
        for index in 0..<TriggerValidator.maxTriggers { try engine.add(makeTrigger(name: "Trigger \(index)")) }
        #expect(throws: TriggerError.invalid) { try engine.add(makeTrigger(name: "One too many")) }
        #expect(engine.triggers.count == TriggerValidator.maxTriggers)
    }
    @Test func noticesCanBeCleared() throws {
        let store = tempStore()
        try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("nonsense".utf8).write(to: store.url)
        let engine = makeEngine(controller: makeController(), store: store)
        engine.load()
        #expect(engine.storeNotice != nil)
        engine.clearNotice()
        #expect(engine.storeNotice == nil)
    }
}
