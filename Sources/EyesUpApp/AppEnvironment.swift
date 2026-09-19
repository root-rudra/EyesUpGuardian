import AppKit
import EyesUpCore

enum Defaults {
    static let presets: [TimeInterval] = [900, 3600, 7200, 14400]
    static let headsUpLead: TimeInterval = 300
    static let extendStep: TimeInterval = 1800
}

/// Builds the real dependencies and connects system events to the controller and trigger engine.
@MainActor
final class AppEnvironment {
    let controller: AwakeController
    let engine: TriggerEngine
    let settings: SettingsController
    let safety: SafetyGuard
    let metrics: MetricsCenter
    let workspace: LiveWorkspaceEvents

    private var observers: [NSObjectProtocol] = []

    init() {
        let inspector = LibprocInspector()
        let scheduler = DispatchTimerScheduler()
        let directory = StorageLocation.directory
        let workspace = LiveWorkspaceEvents()

        controller = AwakeController(
            provider: IOKitPowerAssertions(),
            scheduler: scheduler,
            exitWatcher: KqueueExitWatcher(inspector: inspector),
            inspector: inspector,
            holdStore: JSONFileStore(url: directory.appendingPathComponent("holds.json"), schemaVersion: 1),
            headsUpLead: Defaults.headsUpLead
        )
        engine = TriggerEngine(
            controller: controller,
            factory: LiveConditionMonitorFactory(workspace: workspace, scheduler: scheduler),
            scheduler: scheduler,
            store: JSONFileStore(url: directory.appendingPathComponent("triggers.json"), schemaVersion: 1)
        )
        settings = SettingsController(
            store: JSONFileStore(url: directory.appendingPathComponent("settings.json"), schemaVersion: 1)
        )
        safety = SafetyGuard(controller: controller, thermal: LiveThermalMonitor())
        metrics = MetricsCenter(probes: LiveProbes(), scheduler: scheduler)
        self.workspace = workspace
    }

    func start() {
        settings.onChange = { [weak self] settings in
            guard let self else { return }
            SettingsApplier.apply(settings, controller: controller, engine: engine, safety: safety)
        }
        controller.restore()
        engine.load()      // triggers first, so settings can pause them
        settings.load()
        safety.start()

        let refresh: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated {
                self?.controller.refresh()
                self?.engine.refresh()
                self?.metrics.refresh()
            }
        }
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observers.append(workspaceCenter.addObserver(forName: NSWorkspace.didWakeNotification,
                                                     object: nil, queue: .main, using: refresh))
        observers.append(NotificationCenter.default.addObserver(forName: .NSSystemClockDidChange,
                                                                object: nil, queue: .main, using: refresh))
        observers.append(NotificationCenter.default.addObserver(forName: .NSSystemTimeZoneDidChange,
                                                                object: nil, queue: .main, using: refresh))
    }

    /// Spec §5.1: links do nothing unless the user switched them on.
    var automationEnabled: Bool { settings.settings.automationEnabled }

    func shutdown() {
        engine.shutdown()
        safety.stop()
        controller.shutdown()
    }
}
