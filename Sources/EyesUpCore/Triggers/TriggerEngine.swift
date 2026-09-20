import Foundation
import Observation

/// Whether triggers are paused, and until when (spec §4.5).
public enum TriggerPause: Codable, Hashable, Sendable {
    case none
    case untilResumed
    case until(Date)
}

public enum TriggerError: Error, Equatable, Sendable {
    case invalid

    public var message: String { "Check the trigger's name and settings — something is missing or out of range." }
}

/// Turns condition changes into trigger-owned holds on the controller (spec §5).
@MainActor
@Observable
public final class TriggerEngine {
    public private(set) var triggers: [Trigger] = []
    public private(set) var pause: TriggerPause = .none
    public private(set) var storeNotice: String?

    /// Notices are dismissible: one bad launch shouldn't leave a permanent banner.
    public func clearNotice() { storeNotice = nil }

    public var isPaused: Bool { pause != .none }

    /// Messages for triggers whose `notifyOnChange` is on.
    @ObservationIgnored public var onNotify: ((String) -> Void)?

    @ObservationIgnored private let controller: AwakeController
    @ObservationIgnored private let factory: any ConditionMonitorFactory
    @ObservationIgnored private let clock: any WallClock
    @ObservationIgnored private let scheduler: any TimerScheduling
    @ObservationIgnored private let store: JSONFileStore<[Trigger]>?
    @ObservationIgnored private var monitors: [UUID: any ConditionMonitor] = [:]
    @ObservationIgnored private var conditionMet: [UUID: Bool] = [:]
    @ObservationIgnored private var resumeTask: (any ScheduledTask)?

    public init(
        controller: AwakeController,
        factory: any ConditionMonitorFactory,
        clock: any WallClock = SystemClock(),
        scheduler: any TimerScheduling,
        store: JSONFileStore<[Trigger]>? = nil
    ) {
        self.controller = controller
        self.factory = factory
        self.clock = clock
        self.scheduler = scheduler
        self.store = store
    }

    // MARK: Lifecycle

    /// Reads saved triggers (dropping any that fail validation) and starts their monitors.
    public func load() {
        if let store {
            switch store.load(now: clock.now) {
            case .missing:
                break
            case .loaded(let saved):
                // Cap before validating, so a huge file costs no more work than a normal one.
                let valid = saved.prefix(TriggerValidator.maxTriggers).compactMap(TriggerValidator.sanitized)
                triggers = Array(valid)
                if triggers.count < saved.count {
                    storeNotice = "Some saved triggers were invalid or beyond the limit, and were discarded."
                }
            case .corrupt:
                storeNotice = "Saved triggers couldn't be read, so they were reset."
            }
        }
        for trigger in triggers { startMonitor(for: trigger) }
    }

    public func shutdown() {
        resumeTask?.cancel()
        resumeTask = nil
        for monitor in monitors.values { monitor.stop() }
        monitors.removeAll()
        conditionMet.removeAll()
    }

    /// Re-check everything after a wake, clock change or timezone change.
    public func refresh() {
        if case .until(let date) = pause, date <= clock.now { setPause(.none) }
        for monitor in monitors.values { monitor.reevaluate() }
    }

    // MARK: Editing

    public func add(_ trigger: Trigger) throws {
        guard triggers.count < TriggerValidator.maxTriggers,
              let clean = TriggerValidator.sanitized(trigger) else { throw TriggerError.invalid }
        triggers.append(clean)
        startMonitor(for: clean)
        persist()
    }

    public func update(_ trigger: Trigger) throws {
        guard let clean = TriggerValidator.sanitized(trigger),
              let index = triggers.firstIndex(where: { $0.id == clean.id }) else { throw TriggerError.invalid }
        triggers[index] = clean
        startMonitor(for: clean) // stops the old monitor and drops its hold first
        persist()
    }

    public func remove(id: UUID) {
        triggers.removeAll { $0.id == id }
        stopMonitor(id: id)
        persist()
    }

    public func setEnabled(_ enabled: Bool, id: UUID) {
        guard let index = triggers.firstIndex(where: { $0.id == id }) else { return }
        triggers[index].isEnabled = enabled
        if enabled { startMonitor(for: triggers[index]) } else { stopMonitor(id: id) }
        persist()
    }

    // MARK: Pausing

    public func setPause(_ newPause: TriggerPause) {
        resumeTask?.cancel()
        resumeTask = nil
        pause = newPause

        switch newPause {
        case .none:
            for trigger in triggers where trigger.isEnabled && conditionMet[trigger.id] == true {
                apply(trigger, met: true)
            }
        case .untilResumed:
            controller.removeTriggerHolds()
        case .until(let date):
            controller.removeTriggerHolds()
            resumeTask = scheduler.schedule(at: date) { [weak self] in self?.setPause(.none) }
        }
    }

    // MARK: Private

    private func startMonitor(for trigger: Trigger) {
        stopMonitor(id: trigger.id)
        guard trigger.isEnabled else { return }
        let monitor = factory.makeMonitor(for: trigger.condition)
        monitors[trigger.id] = monitor
        monitor.start { [weak self] met in self?.report(triggerID: trigger.id, met: met) }
    }

    private func stopMonitor(id: UUID) {
        monitors.removeValue(forKey: id)?.stop()
        conditionMet[id] = nil
        controller.endTriggerHold(triggerID: id, grace: 0)
    }

    private func report(triggerID: UUID, met: Bool) {
        guard let trigger = triggers.first(where: { $0.id == triggerID }), trigger.isEnabled else { return }
        guard conditionMet[triggerID] != met else { return } // only edges matter
        conditionMet[triggerID] = met
        guard !isPaused else { return }
        apply(trigger, met: met)
    }

    private func apply(_ trigger: Trigger, met: Bool) {
        if met {
            controller.beginTriggerHold(triggerID: trigger.id, label: trigger.name, policy: trigger.policy)
            if trigger.notifyOnChange { onNotify?("\(trigger.name): keeping your Mac awake.") }
        } else {
            controller.endTriggerHold(triggerID: trigger.id, grace: trigger.grace)
            if trigger.notifyOnChange { onNotify?("\(trigger.name): stopped keeping your Mac awake.") }
        }
    }

    private func persist() {
        guard let store else { return }
        do {
            try store.save(triggers)
        } catch {
            storeNotice = "Couldn't save triggers: \(error.localizedDescription)"
        }
    }
}
