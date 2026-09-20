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
    let history: HistoryController
    let recorder: HistoryRecorder
    let workspace: LiveWorkspaceEvents
    let launchAtLogin = LaunchAtLogin()
    let shortcut = GlobalShortcut()

    /// Set by the app delegate: UI that must react to a settings change.
    var onSettingsChanged: ((AppSettings) -> Void)?

    /// Set by the app delegate: show or hide the floating HUD.
    var onToggleHUD: ((Bool) -> Void)?

    private var observers: [NSObjectProtocol] = []
    private var energySubscription: MetricsSubscription?
    private var energyTimer: Timer?

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
        history = HistoryController(
            store: JSONFileStore(url: directory.appendingPathComponent("history.json"), schemaVersion: 1)
        )
        recorder = HistoryRecorder(history: history)
        self.workspace = workspace
    }

    func start() {
        settings.onChange = { [weak self] settings in
            guard let self else { return }
            SettingsApplier.apply(settings, controller: controller, engine: engine, safety: safety)
            controller.setHeadsUpLead(settings.headsUpLeadMinutes * 60)
            shortcut.apply(enabled: settings.globalShortcutEnabled) { [weak self] in
                self?.toggleKeepAwake()
            }
            onSettingsChanged?(settings)
        }
        controller.restore()
        engine.load()      // triggers first, so settings can pause them
        settings.load()
        safety.start()
        launchAtLogin.syncFromSystem()
        history.load()
        history.prune()
        observeHolds()
        startEnergyTally()

        let refresh: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated {
                self?.controller.refresh()
                self?.engine.refresh()
                self?.metrics.refresh()
                self?.recorder.recordWake()
            }
        }
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observers.append(workspaceCenter.addObserver(forName: NSWorkspace.didWakeNotification,
                                                     object: nil, queue: .main, using: refresh))
        observers.append(workspaceCenter.addObserver(forName: NSWorkspace.willSleepNotification,
                                                     object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.recorder.recordSleep() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .NSSystemClockDidChange,
                                                                object: nil, queue: .main, using: refresh))
        observers.append(NotificationCenter.default.addObserver(forName: .NSSystemTimeZoneDidChange,
                                                                object: nil, queue: .main, using: refresh))
    }

    /// Sessions are recorded from the holds themselves, so every source counts the same way.
    /// What the global shortcut does: the same thing as the menu's keep-awake switch.
    func toggleKeepAwake() {
        if controller.isAwake {
            controller.stopAll()
        } else {
            _ = controller.startIndefinite(policy: controller.currentPolicy)
        }
    }

    private func observeHolds() {
        withObservationTracking {
            _ = controller.holds
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.recorder.holdsChanged(self.controller.holds)
                self.observeHolds()
            }
        }
        recorder.holdsChanged(controller.holds)
    }

    /// Spec §6.3: the one thing that samples while nothing is visible, at 30 s, and only when
    /// watts are actually readable.
    private func startEnergyTally() {
        energySubscription = metrics.subscribe([.power], interval: 30)
        energyTimer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let watts = self.metrics.snapshot.power?.watts else { return }
                self.recorder.energyTick(watts: watts, awake: self.controller.isAwake)
            }
        }
        energyTimer?.tolerance = 5
        if let energyTimer { RunLoop.main.add(energyTimer, forMode: .common) }
    }

    /// Spec §5.1: links do nothing unless the user switched them on.
    var automationEnabled: Bool { settings.settings.automationEnabled }

    func shutdown() {
        recorder.finishOpenSession()
        energySubscription?.cancel()
        energyTimer?.invalidate()
        engine.shutdown()
        safety.stop()
        controller.shutdown()
    }
}
