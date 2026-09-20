import Foundation
import Observation

/// Owns what the app remembers and writes it out. Everything it returns has already been sanitised.
@MainActor
@Observable
public final class HistoryController {
    public private(set) var snapshot = HistorySnapshot()
    public private(set) var storeNotice: String?

    /// Notices are dismissible: one bad launch shouldn't leave a permanent banner.
    public func clearNotice() { storeNotice = nil }

    @ObservationIgnored private let store: JSONFileStore<HistorySnapshot>?
    @ObservationIgnored private let clock: any WallClock

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
        persist()
    }

    public func record(event: SleepWakeEvent) {
        snapshot.sleepWake.append(event)
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
        }
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
        guard let store else { return }
        do {
            try store.save(snapshot.sanitized(now: clock.now))
        } catch {
            storeNotice = "Couldn't save history: \(error.localizedDescription)"
        }
    }
}
