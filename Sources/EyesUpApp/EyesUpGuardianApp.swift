import AppKit
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        let environment = AppEnvironment()
        environment.start()
        let statusItem = StatusItemController(controller: environment.controller)
        statusItem.setPopoverContent(PopoverView(controller: environment.controller, form: PopoverFormState()))
        self.statusItem = statusItem
        self.environment = environment
    }

    func applicationWillTerminate(_ notification: Notification) {
        environment?.shutdown()
    }
}
