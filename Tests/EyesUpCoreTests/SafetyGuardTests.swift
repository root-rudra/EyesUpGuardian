import Foundation
import Testing
@testable import EyesUpCore

@Suite @MainActor struct SafetyGuardTests {
    let provider = FakePowerAssertions()
    let clock = FakeClock()
    let scheduler = FakeScheduler()
    let thermal = FakeThermal()

    func makeController() -> AwakeController {
        AwakeController(provider: provider, clock: clock, scheduler: scheduler,
                        exitWatcher: FakeExitWatcher(), inspector: FakeInspector(), holdStore: nil)
    }

    @Test func criticalThermalStateReleasesEverything() {
        let controller = makeController()
        controller.startIndefinite(policy: .system)
        controller.beginTriggerHold(triggerID: UUID(), label: "Claude running", policy: .system)
        let safety = SafetyGuard(controller: controller, thermal: thermal)
        var notified = false
        safety.onThermalRelease = { notified = true }
        safety.start()

        thermal.change(to: .critical)
        #expect(controller.holds.isEmpty)
        #expect(provider.live.isEmpty)
        #expect(notified)
    }

    @Test func lesserHeatIsLeftAlone() {
        let controller = makeController()
        controller.startIndefinite(policy: .system)
        let safety = SafetyGuard(controller: controller, thermal: thermal)
        safety.start()

        thermal.change(to: .serious)
        #expect(controller.isAwake)
    }

    @Test func switchingTheGuardOffLeavesHoldsAlone() {
        let controller = makeController()
        controller.startIndefinite(policy: .system)
        let safety = SafetyGuard(controller: controller, thermal: thermal)
        safety.thermalAutoRelease = false
        safety.start()

        thermal.change(to: .critical)
        #expect(controller.isAwake)
    }

    @Test func anAlreadyCriticalMacIsHandledAtStart() {
        let controller = makeController()
        controller.startIndefinite(policy: .system)
        thermal.level = .critical
        let safety = SafetyGuard(controller: controller, thermal: thermal)
        safety.start()
        #expect(controller.holds.isEmpty)
    }

    @Test func noNotificationWhenNothingWasHeld() {
        let controller = makeController()
        let safety = SafetyGuard(controller: controller, thermal: thermal)
        var notified = false
        safety.onThermalRelease = { notified = true }
        safety.start()
        thermal.change(to: .critical)
        #expect(!notified)
    }

    @Test func settingsApplierPushesEverySetting() {
        let controller = makeController()
        let engine = TriggerEngine(controller: controller, factory: FakeMonitorFactory(),
                                   clock: clock, scheduler: scheduler, store: nil)
        let safety = SafetyGuard(controller: controller, thermal: thermal)

        SettingsApplier.apply(
            AppSettings(safetyCapHours: 4, thermalAutoRelease: false, automationEnabled: true, triggerPause: .untilResumed),
            controller: controller, engine: engine, safety: safety
        )
        #expect(controller.safetyCap == Double(4 * 3600))
        #expect(!safety.thermalAutoRelease)
        #expect(engine.pause == .untilResumed)

        SettingsApplier.apply(AppSettings(), controller: controller, engine: engine, safety: safety)
        #expect(controller.safetyCap == nil)
        #expect(safety.thermalAutoRelease)
        #expect(engine.pause == .none)
    }
}
