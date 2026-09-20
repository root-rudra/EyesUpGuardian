import Foundation

/// Turns what the controller is doing into what the History tab shows: one session per continuous
/// stretch of being awake, plus the sleep/wake log and the energy tally.
@MainActor
public final class HistoryRecorder {
    private let history: HistoryController
    private let clock: any WallClock
    private var sessionStart: Date?
    private var reasons: Set<String> = []
    private var sources: Set<String> = []
    private var meter = EnergyMeter()

    public init(history: HistoryController, clock: any WallClock = SystemClock()) {
        self.history = history
        self.clock = clock
    }

    /// Call whenever the controller's holds change.
    public func holdsChanged(_ holds: [Hold]) {
        if holds.isEmpty {
            finishOpenSession()
            return
        }
        if sessionStart == nil { sessionStart = clock.now }
        reasons.formUnion(holds.map(\.label))
        sources.formUnion(holds.map { hold in
            switch hold.source {
            case .manual: "manual"
            case .trigger: "trigger"
            case .automation: "automation"
            }
        })
    }

    /// Ends the running session, if any — on the last hold going away, and on quit.
    public func finishOpenSession() {
        guard let start = sessionStart else { return }
        sessionStart = nil
        let session = Session(
            startedAt: start,
            endedAt: clock.now,
            reasons: reasons.sorted(),
            source: sources.sorted().joined(separator: "+")
        )
        reasons.removeAll()
        sources.removeAll()
        guard session.duration > 0 else { return }
        history.record(session: session)
    }

    public func recordSleep() {
        history.record(event: SleepWakeEvent(at: clock.now, kind: .slept))
    }

    public func recordWake() {
        history.record(event: SleepWakeEvent(at: clock.now, kind: .woke))
        meter = EnergyMeter() // the gap across sleep is not energy we measured
    }

    /// One power reading. The meter decides whether enough time passed to count.
    public func energyTick(watts: Double, awake: Bool) {
        guard let tick = meter.accumulate(watts: watts, at: clock.now, awake: awake) else { return }
        history.addEnergy(kilowattHours: tick.kilowattHours, awakeSeconds: tick.awakeSeconds, at: tick.at)
    }
}
