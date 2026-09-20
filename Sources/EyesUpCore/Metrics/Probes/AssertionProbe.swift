import Foundation

/// Which *other* apps are keeping the Mac awake (spec §6.2) — the answer to "why won't it sleep?"
public struct AssertionProbe {
    private let ownPID: Int32

    public init(ownPID: Int32 = getpid()) {
        self.ownPID = ownPID
    }

    public func sample() -> [OtherAssertion]? {
        let relevant: Set<String> = [
            AssertionKind.preventDisplaySleep.ioKitType,
            AssertionKind.preventIdleSystemSleep.ioKitType,
            AssertionKind.preventSystemSleep.ioKitType,
        ]
        let inspector = LibprocInspector()
        var seen: Set<OtherAssertion> = []
        for assertion in SystemAssertions.all() where assertion.pid != ownPID && relevant.contains(assertion.type) {
            let name = ProcessProbe.displayName(inspector.name(of: assertion.pid) ?? "process \(assertion.pid)")
            seen.insert(OtherAssertion(processName: name, type: assertion.type))
        }
        return Array(seen).sorted { $0.processName.localizedCaseInsensitiveCompare($1.processName) == .orderedAscending }
    }
}
