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

/// Raw counters behind the activity triggers and the stats probes.
public protocol SystemCounters: Sendable {
    func cpuTicks() -> (busy: UInt64, total: UInt64)?
    func networkBytes() -> UInt64?
    func diskBytesWritten() -> UInt64?
    /// Bytes received and sent separately; nil when the interface list can't be read.
    func networkBytesSplit() -> (received: UInt64, sent: UInt64)?
    func diskBytesRead() -> UInt64?
    /// Bytes read and written together, from one pass over the disk drivers.
    func diskBytes() -> (read: UInt64, written: UInt64)?
}

extension SystemCounters {
    public func networkBytesSplit() -> (received: UInt64, sent: UInt64)? { nil }
    public func diskBytesRead() -> UInt64? { nil }
    public func diskBytes() -> (read: UInt64, written: UInt64)? { nil }
}

public enum ThermalLevel: Int, Sendable, Comparable, CaseIterable {
    case nominal, fair, serious, critical

    public static func < (lhs: ThermalLevel, rhs: ThermalLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Plain words for the UI: macOS's own names ("nominal", "fair") don't mean much to a reader.
    public var title: String {
        switch self {
        case .nominal: "Normal"
        case .fair: "Warm"
        case .serious: "Hot"
        case .critical: "Too hot"
        }
    }
}

@MainActor
public protocol ThermalMonitoring: AnyObject {
    func currentLevel() -> ThermalLevel
    func observeChanges(_ handler: @escaping @MainActor () -> Void) -> any ScheduledTask
}
