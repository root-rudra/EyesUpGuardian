import Foundation
import Observation

/// Owns what the app remembers and writes it out. Everything it returns has already been sanitised.
@MainActor
@Observable
public final class HistoryController {
    /// How long energy ticks may accumulate in memory before they are written. The tally runs every
    /// 30 s for the life of the process; writing the whole file that often costs far more than the
    /// data is worth, and every tick is re-derivable from the next one anyway.
    public static let energyFlushInterval: TimeInterval = 300

    public private(set) var snapshot = HistorySnapshot()
    public private(set) var storeNotice: String?

    /// Notices are dismissible: one bad launch shouldn't leave a permanent banner.
    public func clearNotice() { storeNotice = nil }

    @ObservationIgnored private let store: JSONFileStore<HistorySnapshot>?
    @ObservationIgnored private let clock: any WallClock
    @ObservationIgnored private var lastEnergyWrite: Date?

    public init(store: JSONFileStore<HistorySnapshot>?, clock: any WallClock = SystemClock()) {
        self.store = store
        self.clock = clock
    }

    public func load() {
        guard let store else { return }
        switch store.load(now: clock.now) {
        case .missing:
            break
        case .loaded(let saved):
            snapshot = saved.sanitized(now: clock.now)
        case .corrupt:
            storeNotice = "Your history couldn't be read, so it was reset."
        }
    }

    public func record(session: Session) {
        snapshot.sessions.append(session)
        snapshot.sessions = Array(snapshot.sessions.suffix(HistorySnapshot.maxSessions))
        persist()
    }

    public func record(event: SleepWakeEvent) {
        snapshot.sleepWake.append(event)
        snapshot.sleepWake = Array(snapshot.sleepWake.suffix(HistorySnapshot.maxEvents))
        persist()
    }

    /// Adds to today's bucket, creating it on the first tick of the day.
    public func addEnergy(kilowattHours: Double, awakeSeconds: TimeInterval, at date: Date) {
        guard kilowattHours.isFinite, kilowattHours >= 0 else { return }
        let day = Calendar.current.startOfDay(for: date)
        if let index = snapshot.energy.firstIndex(where: { Calendar.current.isDate($0.day, inSameDayAs: day) }) {
            snapshot.energy[index].kilowattHours += kilowattHours
            snapshot.energy[index].awakeSeconds += awakeSeconds
        } else {
            snapshot.energy.append(EnergyDay(day: day, kilowattHours: kilowattHours, awakeSeconds: awakeSeconds))
            snapshot.energy = Array(snapshot.energy.suffix(HistorySnapshot.maxEnergyDays))
        }
        // Batched: the running total lives in memory and reaches disk every few minutes, on the
        // next session or sleep/wake event, and on quit.
        guard let last = lastEnergyWrite else { persist(); return }
        guard date.timeIntervalSince(last) >= Self.energyFlushInterval else { return }
        persist()
    }

    /// Writes anything the tally has been holding. Called when the app quits.
    public func flush() {
        persist()
    }

    public func clear() {
        snapshot = HistorySnapshot()
        persist()
    }

    /// Called at launch and daily, so an app left running for months doesn't keep growing.
    public func prune() {
        snapshot = snapshot.sanitized(now: clock.now)
        persist()
    }

    private func persist() {
        lastEnergyWrite = clock.now
        guard let store else { return }
        do {
            // Not sanitised here: everything in `snapshot` arrived through `load` or `prune`, which
            // sanitise, or through this class, which caps what it appends. Re-sanitising on every
            // write means walking the whole history every 30 seconds.
            try store.save(snapshot)
        } catch {
            storeNotice = "Couldn't save history: \(error.localizedDescription)"
        }
    }
}
