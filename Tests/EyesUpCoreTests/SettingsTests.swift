import Foundation
import Testing
@testable import EyesUpCore

@Suite @MainActor struct SettingsTests {
    func tempStore() -> JSONFileStore<AppSettings> {
        JSONFileStore(
            url: FileManager.default.temporaryDirectory.appendingPathComponent("EyesUpTests-\(UUID().uuidString)/settings.json"),
            schemaVersion: 1
        )
    }

    @Test func defaultsAreSafe() {
        let settings = AppSettings()
        #expect(settings.safetyCapHours == nil)
        #expect(settings.thermalAutoRelease)
        #expect(!settings.automationEnabled) // the automation link is off until asked for
        #expect(settings.triggerPause == .none)
    }

    @Test func missingKeysFallBackToDefaults() throws {
        let partial = Data(#"{"automationEnabled":true}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: partial)
        #expect(settings.automationEnabled)
        #expect(settings.thermalAutoRelease)
        #expect(settings.safetyCapHours == nil)
    }

    @Test func validationClampsOutOfRangeValues() {
        #expect(AppSettings(safetyCapHours: 0.5).validated().safetyCapHours == nil)
        #expect(AppSettings(safetyCapHours: 1000).validated().safetyCapHours == nil)
        #expect(AppSettings(safetyCapHours: .nan).validated().safetyCapHours == nil)
        #expect(AppSettings(safetyCapHours: 8).validated().safetyCapHours == 8)
        let farFuture = AppSettings(triggerPause: .until(Date().addingTimeInterval(40 * 86_400)))
        #expect(farFuture.validated().triggerPause == .none)
        #expect(AppSettings(triggerPause: .untilResumed).validated().triggerPause == .untilResumed)
    }

    @Test func updatePersistsAndNotifies() throws {
        let store = tempStore()
        let controller = SettingsController(store: store)
        var seen: [AppSettings] = []
        controller.onChange = { seen.append($0) }

        controller.update { $0.safetyCapHours = 12 }
        #expect(controller.settings.safetyCapHours == 12)
        #expect(seen.last?.safetyCapHours == 12)

        let reloaded = SettingsController(store: store)
        reloaded.load()
        #expect(reloaded.settings.safetyCapHours == 12)
    }

    @Test func updateValidatesBeforeSaving() {
        let controller = SettingsController(store: tempStore())
        controller.update { $0.safetyCapHours = 0.1 }
        #expect(controller.settings.safetyCapHours == nil)
    }

    @Test func corruptSettingsFallBackToDefaultsWithANotice() throws {
        let store = tempStore()
        try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.url)
        let controller = SettingsController(store: store)
        controller.load()
        #expect(controller.settings == AppSettings())
        #expect(controller.storeNotice != nil)
    }
    @Test func readoutDefaultsToTheTimerAndSamplesNothing() {
        #expect(AppSettings().menuBarReadout == .timer)
        #expect(MenuBarReadout.timer.metricIDs.isEmpty)
        #expect(MenuBarReadout.iconOnly.metricIDs.isEmpty)
    }

    @Test func readoutsNameTheMetricsTheyNeed() {
        #expect(MenuBarReadout.timerAndCPU.metricIDs == [.cpu])
        #expect(MenuBarReadout.timerAndPower.metricIDs == [.power])
        #expect(MenuBarReadout.timerCPUAndPower.metricIDs == [.cpu, .power])
    }

    @Test func anUnknownSavedReadoutFallsBackToTheTimer() throws {
        let data = Data(#"{"menuBarReadout":"holographic"}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(settings.menuBarReadout == .timer)
    }
    @Test func hudDefaultsToHiddenAndRejectsAbsurdPositions() {
        #expect(!AppSettings().hudVisible)
        #expect(AppSettings().hudPosition == nil)
        #expect(AppSettings(hudPosition: HUDPosition(x: .nan, y: 10)).validated().hudPosition == nil)
        #expect(AppSettings(hudPosition: HUDPosition(x: 1e9, y: 1e9)).validated().hudPosition == nil)
        #expect(AppSettings(hudPosition: HUDPosition(x: 120, y: 340)).validated().hudPosition == HUDPosition(x: 120, y: 340))
    }
    @Test func newSettingsHaveSensibleDefaults() {
        let settings = AppSettings()
        #expect(settings.electricityRate == nil)
        #expect(settings.presets == [900, 3600, 7200, 14400])
        #expect(settings.headsUpLeadMinutes == 5)
        #expect(!settings.keepDisplayOnByDefault)
    }

    @Test func settingsValidationClampsTheNewFields() {
        #expect(AppSettings(electricityRate: -1).validated().electricityRate == nil)
        #expect(AppSettings(electricityRate: .nan).validated().electricityRate == nil)
        #expect(AppSettings(electricityRate: 99).validated().electricityRate == nil)   // no tariff is $99/kWh
        #expect(AppSettings(electricityRate: 0.32).validated().electricityRate == 0.32)

        #expect(AppSettings(presets: []).validated().presets == AppSettings().presets)
        #expect(AppSettings(presets: [0, -5, 60, 1e12]).validated().presets == [60])
        #expect(AppSettings(presets: Array(repeating: 60, count: 20)).validated().presets.count <= AppSettings.maxPresets)

        #expect(AppSettings(headsUpLeadMinutes: 0).validated().headsUpLeadMinutes == 5)
        #expect(AppSettings(headsUpLeadMinutes: 600).validated().headsUpLeadMinutes == 5)
        #expect(AppSettings(headsUpLeadMinutes: 10).validated().headsUpLeadMinutes == 10)
    }

    @Test func settingsRoundTripThroughExportAndImport() throws {
        var settings = AppSettings()
        settings.electricityRate = 0.28
        settings.presets = [600, 1800]
        settings.menuBarReadout = .timerAndPower
        let data = try settings.exportData()
        #expect(try AppSettings.imported(from: data) == settings)
    }

    @Test func importingRubbishIsRefusedAndChangesNothing() throws {
        let controller = SettingsController(store: tempStore())
        controller.update { $0.electricityRate = 0.3 }
        #expect(throws: (any Error).self) { try controller.importSettings(Data("not json".utf8)) }
        #expect(controller.settings.electricityRate == 0.3)
    }

    @Test func importingValidatesWhatItAccepts() throws {
        let controller = SettingsController(store: tempStore())
        let hostile = Data(#"{"electricityRate": 500, "headsUpLeadMinutes": 9999, "presets": []}"#.utf8)
        try controller.importSettings(hostile)
        #expect(controller.settings.electricityRate == nil)
        #expect(controller.settings.headsUpLeadMinutes == 5)
        #expect(controller.settings.presets == AppSettings().presets)
    }

    @Test func hudPositionsSnapToTheNearestCorner() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let size = CGSize(width: 200, height: 60)
        // Near the top-left, with a 20 pt margin.
        #expect(HUDPosition(x: 60, y: 700).snapped(in: screen, size: size, margin: 20) == HUDPosition(x: 20, y: 720))
        // Near the bottom-right.
        #expect(HUDPosition(x: 900, y: 40).snapped(in: screen, size: size, margin: 20) == HUDPosition(x: 780, y: 20))
        // Dead centre still lands in a corner rather than floating.
        let centred = HUDPosition(x: 400, y: 370).snapped(in: screen, size: size, margin: 20)
        #expect([20.0, 780.0].contains(centred.x))
        #expect([20.0, 720.0].contains(centred.y))
    }

    @Test func clickThroughDefaultsToOff() {
        #expect(!AppSettings().hudClickThrough)
    }

    @Test func everyReadoutNamesTheMetricsItNeeds() {
        #expect(MenuBarReadout.timerAndMemory.metricIDs == [.memory])
        #expect(MenuBarReadout.timerAndTemperature.metricIDs == [.temperature])
        #expect(MenuBarReadout.timerAndNetwork.metricIDs == [.network])
        // Every case must name its metrics, or it would display a stat nothing sampled.
        for readout in MenuBarReadout.allCases where readout != .iconOnly && readout != .timer {
            #expect(!readout.metricIDs.isEmpty, "\(readout) shows a stat but subscribes to nothing")
        }
    }
    /// caffeinate -m and -s exist in the model; until Settings could reach them they were only
    /// reachable by hand-editing holds.json, although the README promised them.
    @Test func theDiskAndACSleepTypesReachTheSessionsTheUserStarts() {
        let controller = AwakeController(provider: FakePowerAssertions(), clock: FakeClock(),
                                         scheduler: FakeScheduler(), exitWatcher: FakeExitWatcher(),
                                         inspector: FakeInspector(), holdStore: nil, headsUpLead: 300)
        let engine = TriggerEngine(controller: controller, factory: FakeMonitorFactory(),
                                   clock: FakeClock(), scheduler: FakeScheduler(), store: nil)
        let safety = SafetyGuard(controller: controller, thermal: FakeThermal())

        var settings = AppSettings()
        settings.keepDiskAwake = true
        settings.onlyOnACPower = true
        SettingsApplier.apply(settings, controller: controller, engine: engine, safety: safety)
        #expect(controller.currentPolicy.contains(.disk))
        #expect(controller.currentPolicy.contains(.systemOnAC))

        settings.keepDiskAwake = false
        settings.onlyOnACPower = false
        SettingsApplier.apply(settings, controller: controller, engine: engine, safety: safety)
        #expect(controller.currentPolicy == .system)
    }

    @Test func energyTrackingIsOnByDefaultAndCanBeTurnedOff() {
        #expect(AppSettings().trackEnergy)
        var settings = AppSettings()
        settings.trackEnergy = false
        let encoded = try! JSONEncoder().encode(settings)
        let decoded = try! JSONDecoder().decode(AppSettings.self, from: encoded)
        #expect(!decoded.trackEnergy)
    }
}
