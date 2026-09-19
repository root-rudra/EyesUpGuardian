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

final class FakeClock: WallClock, @unchecked Sendable {
    var now: Date
    init(_ now: Date = referenceDate) { self.now = now }
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

@MainActor
final class FakeTask: ScheduledTask {
    private(set) var isCancelled = false
    private let onCancel: (@MainActor () -> Void)?
    init(onCancel: (@MainActor () -> Void)? = nil) { self.onCancel = onCancel }
    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        onCancel?()
    }
}

@MainActor
final class FakeScheduler: TimerScheduling {
    struct Entry {
        let date: Date
        let task: FakeTask
        let action: @MainActor @Sendable () -> Void
    }
    private(set) var entries: [Entry] = []
    var pending: [Entry] { entries.filter { !$0.task.isCancelled } }

    func schedule(at date: Date, _ action: @escaping @MainActor @Sendable () -> Void) -> any ScheduledTask {
        let task = FakeTask()
        entries.append(Entry(date: date, task: task, action: action))
        return task
    }

    /// Runs every pending action due at or before `date`, earliest first.
    func runDue(at date: Date) {
        let due = pending.filter { $0.date <= date }.sorted { $0.date < $1.date }
        for entry in due where !entry.task.isCancelled {
            entry.task.cancel()
            entry.action()
        }
    }
}

final class FakeInspector: ProcessInspecting, @unchecked Sendable {
    var identities: [Int32: ProcessIdentity] = [:]
    var names: [Int32: String] = [:]
    func identity(of pid: Int32) -> ProcessIdentity? { identities[pid] }
    func name(of pid: Int32) -> String? { names[pid] }
}

@MainActor
final class FakeExitWatcher: ProcessExitWatching {
    private(set) var watched: [ProcessIdentity: @MainActor @Sendable () -> Void] = [:]

    func watch(_ identity: ProcessIdentity, onExit: @escaping @MainActor @Sendable () -> Void) -> any ScheduledTask {
        watched[identity] = onExit
        return FakeTask { [weak self] in self?.watched[identity] = nil }
    }

    func simulateExit(_ identity: ProcessIdentity) {
        watched.removeValue(forKey: identity)?()
    }
}
