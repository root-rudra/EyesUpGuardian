import Foundation

/// Arms exactly two timers: the earliest hold expiry, and the heads-up before the Mac may sleep.
@MainActor
public final class DeadlineMonitor {
    public var headsUpLead: TimeInterval
    /// Spec §4.5: no hold may run longer than this, whatever its own end says.
    public var safetyCap: TimeInterval?
    public var onExpired: (([UUID]) -> Void)?
    public var onHeadsUp: ((Date) -> Void)?

    private let clock: any WallClock
    private let scheduler: any TimerScheduling
    private var holds: [Hold] = []
    private var expiryTask: (any ScheduledTask)?
    private var headsUpTask: (any ScheduledTask)?
    private var announcedEnd: Date?

    public init(clock: any WallClock, scheduler: any TimerScheduling, headsUpLead: TimeInterval = 300) {
        self.clock = clock
        self.scheduler = scheduler
        self.headsUpLead = headsUpLead
    }

    public func update(holds: [Hold]) {
        self.holds = holds
        expiryTask?.cancel()
        expiryTask = nil
        headsUpTask?.cancel()
        headsUpTask = nil

        let now = clock.now
        let expired = holds.filter { ($0.expiry(safetyCap: safetyCap) ?? .distantFuture) <= now }.map(\.id)
        if !expired.isEmpty {
            onExpired?(expired)
            return
        }

        if let next = holds.compactMap({ $0.expiry(safetyCap: safetyCap) }).min() {
            expiryTask = scheduler.schedule(at: next) { [weak self] in self?.recheck() }
        }

        guard let end = Hold.awakeUntil(holds, safetyCap: safetyCap), end != announcedEnd else { return }
        let fireAt = end.addingTimeInterval(-headsUpLead)
        guard fireAt > now else { return }
        headsUpTask = scheduler.schedule(at: fireAt) { [weak self] in
            self?.announcedEnd = end
            self?.onHeadsUp?(end)
        }
    }

    private func recheck() {
        update(holds: holds)
    }
}
