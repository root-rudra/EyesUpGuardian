import Foundation

@MainActor
public protocol ProcessExitWatching: AnyObject {
    func watch(_ identity: ProcessIdentity, onExit: @escaping @MainActor @Sendable () -> Void) -> any ScheduledTask
}

/// Kernel-notified process exit (kqueue NOTE_EXIT): no polling.
@MainActor
public final class KqueueExitWatcher: ProcessExitWatching {
    private let inspector: any ProcessInspecting

    public init(inspector: any ProcessInspecting) {
        self.inspector = inspector
    }

    public func watch(_ identity: ProcessIdentity, onExit: @escaping @MainActor @Sendable () -> Void) -> any ScheduledTask {
        let source = DispatchSource.makeProcessSource(identifier: identity.pid, eventMask: .exit, queue: .main)
        source.setEventHandler {
            source.cancel()
            MainActor.assumeIsolated { onExit() }
        }
        source.resume()

        // Already gone, or the PID now belongs to a different process: end the hold right away.
        if inspector.identity(of: identity.pid) != identity {
            source.cancel()
            DispatchQueue.main.async { MainActor.assumeIsolated { onExit() } }
        }
        return DispatchSourceTask(source)
    }
}
