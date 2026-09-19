import AppKit
import EyesUpCore
import SwiftUI

@main
struct EyesUpGuardianApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene { Settings { EmptyView() } }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var environment: AppEnvironment?
    private var statusItem: StatusItemController?
    private var dashboard: DashboardWindowController?
    private var hud: HUDWindowController?
    private var headsUp: HeadsUpNotifier?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let environment = AppEnvironment()
        let notifier = HeadsUpNotifier(controller: environment.controller)
        headsUp = notifier

        // Wired before start(): restoring holds, loading settings and the first thermal check can all
        // release a session, and those notices would otherwise be lost.
        environment.engine.onNotify = { [weak notifier] message in
            notifier?.postInfo(message, id: "trigger-\(UUID().uuidString)")
        }
        environment.controller.onSafetyRelease = { [weak notifier] labels in
            notifier?.postInfo("Safety limit reached, so keep-awake stopped: \(labels.joined(separator: ", ")).",
                               id: "safety-cap-\(UUID().uuidString)")
        }
        environment.safety.onThermalRelease = { [weak notifier] in
            notifier?.postInfo("Your Mac got too hot, so EyesUpGuardian let it sleep.", id: "thermal")
        }

        environment.start()

        // A pause restored from settings is otherwise invisible outside the dashboard.
        if environment.engine.isPaused {
            notifier.postInfo("Triggers are paused. Resume them in the dashboard's Triggers tab.", id: "paused")
        }

        let dashboard = DashboardWindowController(environment: environment)
        let hud = HUDWindowController(environment: environment)
        let statusItem = StatusItemController(controller: environment.controller)
        statusItem.onOpenDashboard = { dashboard.show() }
        statusItem.onToggleHUD = { hud.toggle() }
        statusItem.setPopoverContent { PopoverView(
            controller: environment.controller,
            onOpenDashboard: { dashboard.show() },
            form: PopoverFormState(),
            stats: StatsViewModel(center: environment.metrics,
                                  ids: [.cpu, .memory, .power, .temperature, .system, .otherAssertions],
                                  interval: 1),
            onHUDToggle: PopoverView.HUDToggle(isPinned: { hud.isVisible }, toggle: { hud.toggle() })
        ) }
        statusItem.applyReadout(environment.settings.settings.menuBarReadout, center: environment.metrics)
        self.hud = hud
        if environment.settings.settings.hudVisible { hud.show() }
        environment.onSettingsChanged = { [weak statusItem] settings in
            statusItem?.applyReadout(settings.menuBarReadout, center: environment.metrics)
        }
        self.dashboard = dashboard
        self.statusItem = statusItem
        self.environment = environment
    }

    /// Spec §5.1. Every link is parsed strictly, and does nothing unless the user switched links on.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let environment else { return }
        guard environment.automationEnabled else {
            headsUp?.postInfo(AutomationError.disabled.message, id: "automation")
            return
        }
        for url in urls.prefix(5) {
            do {
                let command = try AutomationParser.parse(url, cap: environment.controller.safetyCap)
                headsUp?.postInfo(try environment.controller.apply(command), id: "automation-\(UUID().uuidString)")
            } catch let error as AutomationError {
                headsUp?.postInfo(error.message, id: "automation")
            } catch let error as AwakeError {
                headsUp?.postInfo(error.message, id: "automation")
            } catch {
                headsUp?.postInfo("That automation link couldn't be used.", id: "automation")
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hud?.savePosition()
        environment?.shutdown()
    }
}
