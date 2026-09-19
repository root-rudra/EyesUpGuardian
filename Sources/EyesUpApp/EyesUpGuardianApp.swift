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
    private var headsUp: HeadsUpNotifier?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let environment = AppEnvironment()
        environment.start()
        let notifier = HeadsUpNotifier(controller: environment.controller)
        headsUp = notifier
        environment.engine.onNotify = { [weak notifier] message in
            notifier?.postInfo(message, id: "trigger-\(UUID().uuidString)")
        }
        environment.controller.onSafetyRelease = { [weak notifier] labels in
            notifier?.postInfo("Safety limit reached, so keep-awake stopped: \(labels.joined(separator: ", ")).",
                               id: "safety-cap")
        }
        environment.safety.onThermalRelease = { [weak notifier] in
            notifier?.postInfo("Your Mac got too hot, so EyesUpGuardian let it sleep.", id: "thermal")
        }
        let dashboard = DashboardWindowController(environment: environment)
        let statusItem = StatusItemController(controller: environment.controller)
        statusItem.onOpenDashboard = { dashboard.show() }
        statusItem.setPopoverContent(PopoverView(
            controller: environment.controller,
            onOpenDashboard: { dashboard.show() },
            form: PopoverFormState()
        ))
        self.dashboard = dashboard
        self.statusItem = statusItem
        self.environment = environment
    }

    func applicationWillTerminate(_ notification: Notification) {
        environment?.shutdown()
    }
}
