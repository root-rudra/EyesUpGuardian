import Foundation

public protocol WallClock: Sendable {
    var now: Date { get }
}

public struct SystemClock: WallClock {
    public init() {}
    public var now: Date { Date() }
}

@MainActor
public protocol ScheduledTask: AnyObject {
    func cancel()
}

@MainActor
public protocol TimerScheduling: AnyObject {
    func schedule(at date: Date, _ action: @escaping @MainActor @Sendable () -> Void) -> any ScheduledTask
}

/// One-shot timers on the main queue. Wall-clock deadlines keep counting while the Mac sleeps.
@MainActor
public final class DispatchTimerScheduler: TimerScheduling {
    public init() {}

    public func schedule(at date: Date, _ action: @escaping @MainActor @Sendable () -> Void) -> any ScheduledTask {
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(wallDeadline: .now() + max(0, date.timeIntervalSinceNow), leeway: .seconds(1))
        source.setEventHandler {
            source.cancel()
            MainActor.assumeIsolated { action() }
        }
        source.resume()
        return DispatchSourceTask(source)
    }
}

final class DispatchSourceTask: ScheduledTask {
    private let source: any DispatchSourceProtocol
    init(_ source: any DispatchSourceProtocol) { self.source = source }
    func cancel() { source.cancel() }
}
