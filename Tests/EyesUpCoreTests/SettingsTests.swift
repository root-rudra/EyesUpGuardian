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
}
