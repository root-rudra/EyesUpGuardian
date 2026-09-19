import AppKit
import EyesUpCore

enum Defaults {
    static let presets: [TimeInterval] = [900, 3600, 7200, 14400]
    static let headsUpLead: TimeInterval = 300
    static let extendStep: TimeInterval = 1800
}

/// Builds the real dependencies and connects system events to the controller.
@MainActor
final class AppEnvironment {
    let controller: AwakeController
    private var observers: [NSObjectProtocol] = []

    init() {
        let inspector = LibprocInspector()
        controller = AwakeController(
            provider: IOKitPowerAssertions(),
            scheduler: DispatchTimerScheduler(),
            exitWatcher: KqueueExitWatcher(inspector: inspector),
            inspector: inspector,
            holdStore: JSONFileStore(url: StorageLocation.directory.appendingPathComponent("holds.json"), schemaVersion: 1),
            headsUpLead: Defaults.headsUpLead
        )
    }

    func start() {
        controller.restore()
        let refresh: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.controller.refresh() }
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: refresh))
        observers.append(NotificationCenter.default.addObserver(
            forName: .NSSystemClockDidChange, object: nil, queue: .main, using: refresh))
    }

    func shutdown() {
        controller.shutdown()
    }
}
