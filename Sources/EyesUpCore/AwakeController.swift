import Foundation
import Observation

public enum AwakeError: Error, Equatable, Sendable {
    case invalidDuration
    case dateInPast
    case invalidPID
    case noSuchProcess
    case ownProcess

    public var message: String {
        switch self {
        case .invalidDuration: "Choose a duration between 1 minute and 999 hours."
        case .dateInPast: "That time has already passed."
        case .invalidPID: "Enter a process ID using digits only, like 48213."
        case .noSuchProcess: "No running process has that ID."
        case .ownProcess: "EyesUpGuardian can't watch itself."
        }
    }
}

/// Owns the list of holds (the spec's hold registry) and keeps the engine, timers and watchers in sync with it.
@MainActor
@Observable
public final class AwakeController {
    public nonisolated static let maxManualDuration: TimeInterval = 999 * 3600

    public private(set) var holds: [Hold] = []
    public private(set) var lastError: PowerAssertionError?
    public private(set) var storeNotice: String?

    public var isAwake: Bool { !holds.isEmpty }
    public var awakeUntil: Date? { Hold.awakeUntil(holds, safetyCap: safetyCap) }
    /// Spec §4.5 safety cap, in seconds; nil means no cap.
    public private(set) var safetyCap: TimeInterval?
    /// Labels of holds the safety cap ended, for the notification.
    @ObservationIgnored public var onSafetyRelease: (([String]) -> Void)?
    public var sessionStart: Date? { holds.map(\.createdAt).min() }
    public var displayOn: Bool { holds.contains { !$0.source.isTrigger && $0.policy.contains(.display) } }
    /// The policy "+30m" and notification actions should use for new holds.
    public var currentPolicy: SleepPolicy { displayOn ? [.system, .display] : .system }

    @ObservationIgnored private let provider: any PowerAssertionProviding
    @ObservationIgnored private let engine: AwakeEngine
    @ObservationIgnored private let deadlines: DeadlineMonitor
    @ObservationIgnored private let exitWatcher: any ProcessExitWatching
    @ObservationIgnored private let inspector: any ProcessInspecting
    @ObservationIgnored private let clock: any WallClock
    @ObservationIgnored private let holdStore: JSONFileStore<[Hold]>?
    @ObservationIgnored private let ownPID: Int32
    @ObservationIgnored private var watches: [ProcessIdentity: any ScheduledTask] = [:]

    public init(
        provider: any PowerAssertionProviding,
        clock: any WallClock = SystemClock(),
        scheduler: any TimerScheduling,
        exitWatcher: any ProcessExitWatching,
        inspector: any ProcessInspecting,
        holdStore: JSONFileStore<[Hold]>? = nil,
        headsUpLead: TimeInterval = 300,
        ownPID: Int32 = getpid()
    ) {
        self.provider = provider
        self.clock = clock
        self.exitWatcher = exitWatcher
        self.inspector = inspector
        self.holdStore = holdStore
        self.ownPID = ownPID
        engine = AwakeEngine(provider: provider)
        deadlines = DeadlineMonitor(clock: clock, scheduler: scheduler, headsUpLead: headsUpLead)
        deadlines.onExpired = { [weak self] ids in self?.expire(ids: Set(ids)) }
    }

    // MARK: Starting

    @discardableResult
    public func startTimer(duration: TimeInterval, policy: SleepPolicy) throws -> Hold {
        guard duration > 0, duration <= Self.maxManualDuration else { throw AwakeError.invalidDuration }
        let now = clock.now
        return replaceManualSession(with: Hold(
            label: "Timer \(TimeFormatting.duration(duration))", policy: policy,
            end: .deadline(now.addingTimeInterval(duration)), createdAt: now
        ))
    }

    @discardableResult
    public func startIndefinite(policy: SleepPolicy) -> Hold {
        replaceManualSession(with: Hold(label: "Indefinitely", policy: policy, end: .indefinite, createdAt: clock.now))
    }

    @discardableResult
    public func startUntil(_ date: Date, policy: SleepPolicy) throws -> Hold {
        let now = clock.now
        guard date > now else { throw AwakeError.dateInPast }
        guard date.timeIntervalSince(now) <= Self.maxManualDuration else { throw AwakeError.invalidDuration }
        return replaceManualSession(with: Hold(label: Self.untilLabel(date), policy: policy, end: .deadline(date), createdAt: now))
    }

    @discardableResult
    public func watchProcess(pid: Int32, policy: SleepPolicy, grace: TimeInterval? = nil) throws -> Hold {
        guard pid > 0 else { throw AwakeError.invalidPID }
        guard pid != ownPID else { throw AwakeError.ownProcess }
        guard let identity = inspector.identity(of: pid) else { throw AwakeError.noSuchProcess }
        let name = String((inspector.name(of: pid) ?? "process").prefix(40))
        let hold = Hold(label: "PID \(pid) · \(name)", policy: policy, end: .processExit(identity), grace: grace, createdAt: clock.now)
        holds.append(hold)
        commit()
        return hold
    }

    /// Validates user-typed PIDs: ASCII digits only, 1...Int32.max.
    public nonisolated static func parsePID(_ text: String) throws -> Int32 {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 10,
              trimmed.unicodeScalars.allSatisfy({ ("0"..."9").contains($0) }),
              let pid = Int32(trimmed), pid > 0 else { throw AwakeError.invalidPID }
        return pid
    }

    // MARK: Changing

    public func extend(by seconds: TimeInterval, policy: SleepPolicy) throws {
        guard seconds > 0, seconds <= Self.maxManualDuration else { throw AwakeError.invalidDuration }
        var extended = false
        // Only the user's own sessions: a link's session keeps the ceiling `apply(.extend)` gives it.
        for index in holds.indices where holds[index].source == .manual {
            guard case .deadline(let date) = holds[index].end else { continue }
            let newDate = date.addingTimeInterval(seconds)
            holds[index].end = .deadline(newDate)
            holds[index].label = Self.untilLabel(newDate)
            extended = true
        }
        if extended { commit() } else { try startTimer(duration: seconds, policy: policy) }
    }

    public func setDisplayOn(_ on: Bool) {
        for index in holds.indices where !holds[index].source.isTrigger {
            if on { holds[index].policy.insert(.display) } else { holds[index].policy.remove(.display) }
        }
        commit()
    }

    public func stop(id: UUID) {
        remove(ids: [id])
    }

    public func stopAll() {
        remove(ids: Set(holds.filter { !$0.source.isTrigger }.map(\.id)))
    }

    /// caffeinate -u
    public func nudgeDisplay() {
        provider.declareUserActivity(name: "EyesUpGuardian: nudge display")
    }

    // MARK: Trigger holds

    /// Takes (or refreshes) the hold a trigger owns. Trigger holds have no end of their own.
    @discardableResult
    public func beginTriggerHold(triggerID: UUID, label: String, policy: SleepPolicy) -> Hold {
        if let index = holds.firstIndex(where: { $0.source == .trigger(triggerID) }) {
            holds[index].end = .triggerControlled // cancels any grace countdown
            holds[index].label = label
            holds[index].policy = policy
            commit()
            return holds[index]
        }
        let hold = Hold(source: .trigger(triggerID), label: label, policy: policy,
                        end: .triggerControlled, createdAt: clock.now)
        holds.append(hold)
        commit()
        return hold
    }

    /// The trigger's condition ended: drop the hold now, or after its grace period.
    public func endTriggerHold(triggerID: UUID, grace: TimeInterval) {
        guard let index = holds.firstIndex(where: { $0.source == .trigger(triggerID) }) else { return }
        guard grace > 0 else {
            remove(ids: [holds[index].id])
            return
        }
        holds[index].end = .deadline(clock.now.addingTimeInterval(grace))
        commit()
    }

    public func removeTriggerHolds() {
        remove(ids: Set(holds.filter(\.source.isTrigger).map(\.id)))
    }

    public func hasTriggerHold(triggerID: UUID) -> Bool {
        holds.contains { $0.source == .trigger(triggerID) }
    }

    // MARK: Automation (spec §5.1)

    /// Runs an already-validated link command. Automation only ever touches its own holds,
    /// so a link can never cancel a session you started by hand.
    @discardableResult
    public func apply(_ command: AutomationCommand) throws -> String {
        switch command {
        case .start(let duration, let display):
            let policy: SleepPolicy = display ? [.system, .display] : .system
            let now = clock.now
            switch duration {
            case .finite(let requested):
                guard requested > 0, requested <= Self.maxManualDuration else { throw AwakeError.invalidDuration }
                // Belt and braces: the parser already clamps, but a link's session is never longer than this.
                let seconds = min(requested, min(AutomationParser.maxDuration, safetyCap ?? .greatestFiniteMagnitude))
                holds.removeAll { $0.source == .automation }
                holds.append(Hold(source: .automation, label: "Automation \(TimeFormatting.duration(seconds))",
                                  policy: policy, end: .deadline(now.addingTimeInterval(seconds)), createdAt: now))
                commit()
                return "Automation: keeping your Mac awake for \(TimeFormatting.duration(seconds))."
            case .infinite:
                // A link may never hold with no end; "inf" means the longest a link may ask for.
                return try apply(.start(duration: .finite(AutomationParser.maxDuration), display: display))
            }
        case .stop:
            remove(ids: Set(holds.filter { $0.source == .automation }.map(\.id)))
            return "Automation: stopped its keep-awake session."
        case .extend(let seconds):
            guard seconds > 0, seconds <= Self.maxManualDuration else { throw AwakeError.invalidDuration }
            var extended = false
            // A link may never push its own session past the link cap, or past the safety cap if that is lower.
            let limit = min(AutomationParser.maxDuration, safetyCap ?? .greatestFiniteMagnitude)
            for index in holds.indices where holds[index].source == .automation {
                guard case .deadline(let date) = holds[index].end else { continue }
                let ceiling = holds[index].createdAt.addingTimeInterval(limit)
                let newDate = min(date.addingTimeInterval(seconds), ceiling)
                holds[index].end = .deadline(newDate)
                holds[index].label = "Automation until " + newDate.formatted(date: .omitted, time: .shortened)
                extended = true
            }
            if extended {
                commit()
            } else {
                return try apply(.start(duration: .finite(seconds), display: false))
            }
            return "Automation: extended by \(TimeFormatting.duration(seconds))."
        }
    }
    // MARK: Safety

    public func setSafetyCap(_ cap: TimeInterval?) {
        safetyCap = cap.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        deadlines.safetyCap = safetyCap
        commit()
    }

    /// Thermal emergency (spec §4.5): drop every hold, whatever its source.
    public func releaseAllForSafety() {
        holds.removeAll()
        commit()
    }

    // MARK: Lifecycle

    public func restore() {
        if let holdStore {
            switch holdStore.load(now: clock.now) {
            case .missing:
                break
            case .loaded(let saved):
                let valid = saved.compactMap { HoldRestorer.sanitized($0, now: clock.now) }
                if valid.count < saved.count {
                    storeNotice = "Some saved keep-awake sessions were invalid and were discarded."
                }
                holds = HoldRestorer.restorable(valid, now: clock.now, inspector: inspector)
            case .corrupt:
                storeNotice = "Saved keep-awake sessions couldn't be read, so they were reset."
            }
        }
        commit()
    }

    /// Re-evaluate after wake or a clock change so passed deadlines end immediately.
    public func refresh() {
        commit()
    }

    /// Deliberate quit: stop everything and remember nothing.
    public func shutdown() {
        holds.removeAll()
        commit()
    }

    public func setHeadsUpHandler(_ handler: @escaping (Date) -> Void) {
        deadlines.onHeadsUp = handler
    }

    // MARK: Private

    private func replaceManualSession(with hold: Hold) -> Hold {
        holds.removeAll(where: \.isManualSession)
        holds.append(hold)
        commit()
        return hold
    }

    private func remove(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        holds.removeAll { ids.contains($0.id) }
        commit()
    }

    /// One watch covers every hold waiting on the same process, so they all end in a single pass.
    private func processExited(identity: ProcessIdentity) {
        watches[identity] = nil
        var expired: Set<UUID> = []
        var changed = false
        for index in holds.indices where holds[index].end == .processExit(identity) {
            if let grace = holds[index].grace, grace > 0 {
                holds[index].end = .deadline(clock.now.addingTimeInterval(grace))
                holds[index].grace = nil
                holds[index].label += " · exited"
                changed = true
            } else {
                expired.insert(holds[index].id)
            }
        }
        if !expired.isEmpty {
            remove(ids: expired)
        } else if changed {
            commit()
        }
    }

    /// Holds whose own end has not arrived were ended by the safety cap, so the user is told.
    private func expire(ids: Set<UUID>) {
        let now = clock.now
        let capped = holds.filter { ids.contains($0.id) && ($0.effectiveDeadline ?? .distantFuture) > now }
        remove(ids: ids)
        if !capped.isEmpty { onSafetyRelease?(capped.map(\.label)) }
    }

    private func commit() {
        engine.reconcile(holds: holds)
        lastError = engine.lastError
        syncWatches()
        persist()
        deadlines.update(holds: holds)
    }

    private func syncWatches() {
        var wanted: Set<ProcessIdentity> = []
        for hold in holds {
            if case .processExit(let identity) = hold.end { wanted.insert(identity) }
        }
        for (identity, task) in watches where !wanted.contains(identity) {
            task.cancel()
            watches[identity] = nil
        }
        for identity in wanted where watches[identity] == nil {
            watches[identity] = exitWatcher.watch(identity) { [weak self] in self?.processExited(identity: identity) }
        }
    }

    private func persist() {
        guard let holdStore else { return }
        do {
            try holdStore.save(holds)
        } catch {
            storeNotice = "Couldn't save keep-awake sessions: \(error.localizedDescription)"
        }
    }

    private static func untilLabel(_ date: Date) -> String {
        "Until " + date.formatted(date: .omitted, time: .shortened)
    }
}
