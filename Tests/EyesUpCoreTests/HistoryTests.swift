import Foundation
import Testing
@testable import EyesUpCore

@Suite @MainActor struct HistoryTests {
    let clock = FakeClock()

    func tempStore() -> JSONFileStore<HistorySnapshot> {
        JSONFileStore(
            url: FileManager.default.temporaryDirectory.appendingPathComponent("EyesUpTests-\(UUID().uuidString)/history.json"),
            schemaVersion: 1
        )
    }

    private func session(_ offsetHours: Double, hours: Double = 1, reasons: [String] = ["Timer 1h"]) -> Session {
        let start = referenceDate.addingTimeInterval(offsetHours * 3600)
        return Session(startedAt: start, endedAt: start.addingTimeInterval(hours * 3600), reasons: reasons, source: "manual")
    }

    @Test func sessionsAndTotalsAddUp() {
        var snapshot = HistorySnapshot()
        snapshot.sessions = [session(-5, hours: 2), session(-2, hours: 0.5)]
        #expect(snapshot.awakeSeconds(since: referenceDate.addingTimeInterval(-24 * 3600), now: referenceDate) == 9000)
        #expect(snapshot.sessions.first?.duration == 7200)
    }

    @Test func historyIsPrunedByAge() {
        var snapshot = HistorySnapshot()
        snapshot.sessions = [session(-24 * 100), session(-24)] // 100 days old, 1 day old
        snapshot.energy = [
            EnergyDay(day: referenceDate.addingTimeInterval(-100 * 86_400), kilowattHours: 1, awakeSeconds: 3600),
            EnergyDay(day: referenceDate.addingTimeInterval(-86_400), kilowattHours: 2, awakeSeconds: 3600),
        ]
        let clean = snapshot.sanitized(now: referenceDate)
        #expect(clean.sessions.count == 1)
        #expect(clean.energy.count == 1)
    }

    @Test func historyIsCappedBeforeValidation() {
        var snapshot = HistorySnapshot()
        snapshot.sessions = (0..<(HistorySnapshot.maxSessions + 500)).map { session(-Double($0) / 24) }
        snapshot.sleepWake = (0..<(HistorySnapshot.maxEvents + 500)).map {
            SleepWakeEvent(at: referenceDate.addingTimeInterval(-Double($0) * 60), kind: .woke)
        }
        let clean = snapshot.sanitized(now: referenceDate)
        #expect(clean.sessions.count <= HistorySnapshot.maxSessions)
        #expect(clean.sleepWake.count <= HistorySnapshot.maxEvents)
    }

    @Test func absurdEntriesAreDropped() {
        var snapshot = HistorySnapshot()
        let start = referenceDate.addingTimeInterval(-3600)
        snapshot.sessions = [
            Session(startedAt: start, endedAt: start.addingTimeInterval(-60), reasons: [], source: "manual"),   // ends before it starts
            Session(startedAt: referenceDate.addingTimeInterval(86_400), endedAt: referenceDate.addingTimeInterval(90_000),
                    reasons: [], source: "manual"),                                                            // in the future
            Session(startedAt: start, endedAt: start.addingTimeInterval(400 * 86_400), reasons: [], source: "manual"), // absurd length
            session(-1, reasons: ["Timer 1h\u{202E}\u{000A}fake"]),                                             // spoofed reason
        ]
        snapshot.energy = [
            EnergyDay(day: referenceDate, kilowattHours: .nan, awakeSeconds: 0),
            EnergyDay(day: referenceDate, kilowattHours: -5, awakeSeconds: 0),
            EnergyDay(day: referenceDate.addingTimeInterval(-3600), kilowattHours: 1.5, awakeSeconds: 3600),
        ]
        let clean = snapshot.sanitized(now: referenceDate)
        #expect(clean.sessions.count == 1)
        #expect(clean.sessions.first?.reasons.first?.contains("\n") == false)
        #expect(clean.sessions.first?.reasons.first?.unicodeScalars.contains { $0.properties.generalCategory == .format } == false)
        #expect(clean.energy.count == 1)
        #expect(clean.energy.first?.kilowattHours == 1.5)
    }

    @Test func recordingPersistsAndReloads() throws {
        let store = tempStore()
        let controller = HistoryController(store: store, clock: clock)
        controller.record(session: session(-1))
        controller.record(event: SleepWakeEvent(at: referenceDate, kind: .slept))
        controller.addEnergy(kilowattHours: 0.25, awakeSeconds: 900, at: referenceDate)

        let reloaded = HistoryController(store: store, clock: clock)
        reloaded.load()
        #expect(reloaded.snapshot.sessions.count == 1)
        #expect(reloaded.snapshot.sleepWake.count == 1)
        #expect(reloaded.snapshot.energy.first?.kilowattHours == 0.25)
    }

    @Test func energyForOneDayAccumulates() {
        let controller = HistoryController(store: nil, clock: clock)
        controller.addEnergy(kilowattHours: 0.1, awakeSeconds: 600, at: referenceDate)
        controller.addEnergy(kilowattHours: 0.2, awakeSeconds: 600, at: referenceDate.addingTimeInterval(3600))
        #expect(controller.snapshot.energy.count == 1)
        #expect((controller.snapshot.energy.first?.kilowattHours ?? 0) - 0.3 < 0.0001)
    }

    @Test func clearRemovesEverything() throws {
        let store = tempStore()
        let controller = HistoryController(store: store, clock: clock)
        controller.record(session: session(-1))
        controller.clear()
        #expect(controller.snapshot.sessions.isEmpty)

        let reloaded = HistoryController(store: store, clock: clock)
        reloaded.load()
        #expect(reloaded.snapshot.sessions.isEmpty)
    }

    @Test func aCorruptHistoryStartsCleanWithANotice() throws {
        let store = tempStore()
        try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("nonsense".utf8).write(to: store.url)
        let controller = HistoryController(store: store, clock: clock)
        controller.load()
        #expect(controller.snapshot.sessions.isEmpty)
        #expect(controller.storeNotice != nil)
    }
}
