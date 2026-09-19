import Foundation

/// Builds the real monitor for each condition. The workspace comes from the app layer (NSWorkspace).
@MainActor
public final class LiveConditionMonitorFactory: ConditionMonitorFactory {
    private let workspace: any WorkspaceEvents
    private let clock: any WallClock
    private let scheduler: any TimerScheduling
    private let counters: any SystemCounters
    private let lister: any ProcessLister
    private let displays: any DisplayInventory
    private let power: any PowerSourceInfo

    public init(
        workspace: any WorkspaceEvents,
        clock: any WallClock = SystemClock(),
        scheduler: any TimerScheduling,
        counters: any SystemCounters = LiveSystemCounters(),
        lister: any ProcessLister = LiveProcessLister(),
        displays: any DisplayInventory = LiveDisplayInventory(),
        power: any PowerSourceInfo = LivePowerSourceInfo()
    ) {
        self.workspace = workspace
        self.clock = clock
        self.scheduler = scheduler
        self.counters = counters
        self.lister = lister
        self.displays = displays
        self.power = power
    }

    public func makeMonitor(for condition: TriggerCondition) -> any ConditionMonitor {
        switch condition {
        case .appRunning(let bundleIDs):
            AppRunningMonitor(bundleIDs: bundleIDs, workspace: workspace)
        case .processRunning(let names):
            ProcessRunningMonitor(names: names, lister: lister, clock: clock, scheduler: scheduler)
        case .schedule(let schedule):
            ScheduleMonitor(schedule: schedule, clock: clock, scheduler: scheduler)
        case .cpuBusy(let threshold):
            ActivityMonitor(kind: .cpu, threshold: threshold, counters: counters, clock: clock, scheduler: scheduler)
        case .networkBusy(let threshold):
            ActivityMonitor(kind: .network, threshold: threshold, counters: counters, clock: clock, scheduler: scheduler)
        case .diskBusy(let threshold):
            ActivityMonitor(kind: .disk, threshold: threshold, counters: counters, clock: clock, scheduler: scheduler)
        case .displayConnected(let match):
            DisplayConnectedMonitor(match: match, displays: displays)
        case .onACPower:
            PowerSourceMonitor(power: power)
        }
    }
}
