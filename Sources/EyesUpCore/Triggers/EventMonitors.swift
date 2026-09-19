import Foundation

/// True while any of the chosen apps is running. Bundle IDs can't be spoofed by renaming an app.
@MainActor
public final class AppRunningMonitor: ConditionMonitor {
    private let bundleIDs: Set<String>
    private let workspace: any WorkspaceEvents
    private var report: (@MainActor (Bool) -> Void)?
    private var observation: (any ScheduledTask)?

    public init(bundleIDs: [String], workspace: any WorkspaceEvents) {
        self.bundleIDs = Set(bundleIDs)
        self.workspace = workspace
    }

    public func start(_ report: @escaping @MainActor (Bool) -> Void) {
        self.report = report
        observation = workspace.observeChanges { [weak self] in self?.evaluate() }
        evaluate()
    }

    public func stop() {
        observation?.cancel()
        observation = nil
        report = nil
    }

    public func reevaluate() { evaluate() }

    private func evaluate() {
        report?(!workspace.runningBundleIDs().isDisjoint(with: bundleIDs))
    }
}

/// True while a particular display is plugged in.
@MainActor
public final class DisplayConnectedMonitor: ConditionMonitor {
    private let match: DisplayMatch
    private let displays: any DisplayInventory
    private var report: (@MainActor (Bool) -> Void)?
    private var observation: (any ScheduledTask)?

    public init(match: DisplayMatch, displays: any DisplayInventory) {
        self.match = match
        self.displays = displays
    }

    public func start(_ report: @escaping @MainActor (Bool) -> Void) {
        self.report = report
        observation = displays.observeChanges { [weak self] in self?.evaluate() }
        evaluate()
    }

    public func stop() {
        observation?.cancel()
        observation = nil
        report = nil
    }

    public func reevaluate() { evaluate() }

    private func evaluate() {
        report?(displays.connectedDisplays().contains { $0.matches(match) })
    }
}

/// True while the Mac is on AC power (always true for a desktop; useful for laptops).
@MainActor
public final class PowerSourceMonitor: ConditionMonitor {
    private let power: any PowerSourceInfo
    private var report: (@MainActor (Bool) -> Void)?
    private var observation: (any ScheduledTask)?

    public init(power: any PowerSourceInfo) {
        self.power = power
    }

    public func start(_ report: @escaping @MainActor (Bool) -> Void) {
        self.report = report
        observation = power.observeChanges { [weak self] in self?.evaluate() }
        evaluate()
    }

    public func stop() {
        observation?.cancel()
        observation = nil
        report = nil
    }

    public func reevaluate() { evaluate() }

    private func evaluate() { report?(power.isOnACPower()) }
}

/// True inside the schedule's window. One timer is armed for the next boundary.
@MainActor
public final class ScheduleMonitor: ConditionMonitor {
    private let schedule: Schedule
    private let clock: any WallClock
    private let scheduler: any TimerScheduling
    /// Read fresh each time so a timezone change is picked up.
    private let calendar: @MainActor () -> Calendar
    private var report: (@MainActor (Bool) -> Void)?
    private var task: (any ScheduledTask)?

    public init(
        schedule: Schedule,
        clock: any WallClock,
        scheduler: any TimerScheduling,
        calendar: @escaping @MainActor () -> Calendar = { Calendar.current }
    ) {
        self.schedule = schedule
        self.clock = clock
        self.scheduler = scheduler
        self.calendar = calendar
    }

    public func start(_ report: @escaping @MainActor (Bool) -> Void) {
        self.report = report
        evaluate()
    }

    public func stop() {
        task?.cancel()
        task = nil
        report = nil
    }

    public func reevaluate() { evaluate() }

    private func evaluate() {
        task?.cancel()
        task = nil
        let now = clock.now
        let currentCalendar = calendar()
        report?(schedule.isActive(at: now, calendar: currentCalendar))
        if let next = schedule.nextBoundary(after: now, calendar: currentCalendar) {
            task = scheduler.schedule(at: next) { [weak self] in self?.evaluate() }
        }
    }
}
