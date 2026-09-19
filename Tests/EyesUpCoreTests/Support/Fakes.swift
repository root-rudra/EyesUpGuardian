import Foundation
@testable import EyesUpCore

let referenceDate = Date(timeIntervalSince1970: 1_000_000)

func makeHold(
    label: String = "Test hold",
    policy: SleepPolicy = .system,
    end: HoldEnd = .indefinite,
    grace: TimeInterval? = nil,
    source: HoldSource = .manual,
    createdAt: Date = referenceDate
) -> Hold {
    Hold(source: source, label: label, policy: policy, end: end, grace: grace, createdAt: createdAt)
}

@MainActor
final class FakePowerAssertions: PowerAssertionProviding {
    private(set) var live: [UInt32: (kind: AssertionKind, name: String)] = [:]
    private(set) var createCount = 0
    private(set) var userActivityCount = 0
    var failingKinds: Set<AssertionKind> = []
    private var nextID: UInt32 = 1

    var liveKinds: Set<AssertionKind> { Set(live.values.map(\.kind)) }
    var liveNames: Set<String> { Set(live.values.map(\.name)) }

    func create(_ kind: AssertionKind, name: String) throws -> UInt32 {
        if failingKinds.contains(kind) { throw PowerAssertionError(kind: kind, code: -536870201) }
        createCount += 1
        let id = nextID
        nextID += 1
        live[id] = (kind, name)
        return id
    }

    func rename(_ id: UInt32, to name: String) { live[id]?.name = name }
    func release(_ id: UInt32) { live[id] = nil }
    func declareUserActivity(name: String) { userActivityCount += 1 }
}
