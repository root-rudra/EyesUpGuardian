import AppKit
import EyesUpCore

/// NSWorkspace lives in AppKit, which EyesUpCore must not import, so the app supplies it.
@MainActor
final class LiveWorkspaceEvents: WorkspaceEvents {
    func runningBundleIDs() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    func observeChanges(_ handler: @escaping @MainActor () -> Void) -> any ScheduledTask {
        let center = NSWorkspace.shared.notificationCenter
        let forward: @Sendable (Notification) -> Void = { _ in MainActor.assumeIsolated { handler() } }
        let launched = center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification,
                                          object: nil, queue: .main, using: forward)
        let terminated = center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                                            object: nil, queue: .main, using: forward)
        return WorkspaceObservation {
            center.removeObserver(launched)
            center.removeObserver(terminated)
        }
    }

    /// Apps with a Dock icon, for the trigger editor's picker.
    func runningApps() -> [(bundleID: String, name: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in app.bundleIdentifier.map { (bundleID: $0, name: app.localizedName ?? $0) } }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

@MainActor
final class WorkspaceObservation: ScheduledTask {
    private var onCancel: (@MainActor () -> Void)?

    init(_ onCancel: @escaping @MainActor () -> Void) { self.onCancel = onCancel }

    func cancel() {
        onCancel?()
        onCancel = nil
    }
}
