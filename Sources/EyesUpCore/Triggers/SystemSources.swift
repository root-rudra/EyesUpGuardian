import Foundation

/// Running applications. Implemented in the app layer with NSWorkspace, which is AppKit.
@MainActor
public protocol WorkspaceEvents: AnyObject {
    func runningBundleIDs() -> Set<String>
    func observeChanges(_ handler: @escaping @MainActor () -> Void) -> any ScheduledTask
}

@MainActor
public protocol DisplayInventory: AnyObject {
    func connectedDisplays() -> [DisplayMatch]
    func observeChanges(_ handler: @escaping @MainActor () -> Void) -> any ScheduledTask
}

@MainActor
public protocol PowerSourceInfo: AnyObject {
    func isOnACPower() -> Bool
    func observeChanges(_ handler: @escaping @MainActor () -> Void) -> any ScheduledTask
}

/// Names of processes this user can see. macOS hides other users' and root's names from libproc.
public protocol ProcessLister: Sendable {
    func runningProcessNames() -> Set<String>
}

/// Raw counters behind the activity triggers.
public protocol SystemCounters: Sendable {
    func cpuTicks() -> (busy: UInt64, total: UInt64)?
    func networkBytes() -> UInt64?
    func diskBytesWritten() -> UInt64?
}

public enum ThermalLevel: Int, Sendable, Comparable, CaseIterable {
    case nominal, fair, serious, critical

    public static func < (lhs: ThermalLevel, rhs: ThermalLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

@MainActor
public protocol ThermalMonitoring: AnyObject {
    func currentLevel() -> ThermalLevel
    func observeChanges(_ handler: @escaping @MainActor () -> Void) -> any ScheduledTask
}
