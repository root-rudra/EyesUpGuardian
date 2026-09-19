import Foundation
import IOKit.pwr_mgt

/// Real power assertions via IOKit: the same mechanism `caffeinate` uses, without launching it.
@MainActor
public final class IOKitPowerAssertions: PowerAssertionProviding {
    public init() {}

    public func create(_ kind: AssertionKind, name: String) throws -> UInt32 {
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kind.ioKitType as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            name as CFString,
            &id
        )
        guard result == kIOReturnSuccess else { throw PowerAssertionError(kind: kind, code: result) }
        return id
    }

    public func rename(_ id: UInt32, to name: String) {
        _ = IOPMAssertionSetProperty(id, "AssertName" as CFString, name as CFString)
    }

    public func release(_ id: UInt32) {
        _ = IOPMAssertionRelease(id)
    }

    public func declareUserActivity(name: String) {
        var id = IOPMAssertionID(0)
        guard IOPMAssertionDeclareUserActivity(name as CFString, kIOPMUserActiveLocal, &id) == kIOReturnSuccess else { return }
        // Match caffeinate -u, which holds the activity assertion for 5 seconds.
        let assertionID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { _ = IOPMAssertionRelease(assertionID) }
    }
}

/// A power assertion held by any process on the system.
public struct SystemAssertion: Hashable, Sendable {
    public let pid: Int32
    public let type: String
    public let name: String
}

public enum SystemAssertions {
    public static func all() -> [SystemAssertion] {
        var raw: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&raw) == kIOReturnSuccess,
              let byProcess = raw?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return [] }
        return byProcess.flatMap { pid, list in
            list.map {
                SystemAssertion(
                    pid: pid.int32Value,
                    type: $0["AssertType"] as? String ?? "",
                    name: $0["AssertName"] as? String ?? ""
                )
            }
        }
    }

    public static func forProcess(_ pid: Int32) -> [SystemAssertion] {
        all().filter { $0.pid == pid }
    }
}
