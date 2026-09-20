import Darwin
import Foundation

public enum ProcessControlError: Error, Equatable, Sendable {
    case notYours
    case gone
    case recycled
    case signalRefused

    public var message: String {
        switch self {
        case .notYours: "That process belongs to another user, so EyesUpGuardian can't quit it."
        case .gone: "That process has already ended."
        case .recycled: "That process ended and its ID now belongs to something else, so nothing was quit."
        case .signalRefused: "macOS refused to quit that process."
        }
    }
}

/// Sending signals, behind a protocol so tests never signal a real process.
public protocol ProcessSignalling: Sendable {
    func send(_ signal: Int32, to pid: Int32) -> Bool
}

public struct POSIXSignaller: ProcessSignalling {
    public init() {}

    public func send(_ signal: Int32, to pid: Int32) -> Bool {
        pid > 0 && kill(pid, signal) == 0
    }
}

/// Quit / Force Quit for the user's own processes only (spec §7.3, §9.6).
/// The identity is re-verified immediately before the signal, so a recycled PID is never hit.
public struct ProcessControl {
    private let inspector: any ProcessInspecting
    private let ownUID: uid_t
    private let signaller: any ProcessSignalling

    public init(
        inspector: any ProcessInspecting = LibprocInspector(),
        ownUID: uid_t = getuid(),
        signaller: any ProcessSignalling = POSIXSignaller()
    ) {
        self.inspector = inspector
        self.ownUID = ownUID
        self.signaller = signaller
    }

    public func quit(_ identity: ProcessIdentity, force: Bool) throws {
        guard let current = inspector.identity(of: identity.pid) else { throw ProcessControlError.gone }
        guard current == identity else { throw ProcessControlError.recycled }
        guard let uid = inspector.ownerUID(of: identity.pid), uid == ownUID else { throw ProcessControlError.notYours }
        guard signaller.send(force ? SIGKILL : SIGTERM, to: identity.pid) else {
            throw ProcessControlError.signalRefused
        }
    }
}
