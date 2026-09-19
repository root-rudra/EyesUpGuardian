import Foundation
import Testing
@testable import EyesUpCore

@Suite struct StoreTests {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("EyesUpTests-\(UUID().uuidString)")
    var url: URL { directory.appendingPathComponent("holds.json") }
    var store: JSONFileStore<[Hold]> { JSONFileStore(url: url, schemaVersion: 1) }

    private func write(_ text: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func assertMovedAside(_ result: StoreLoadResult<[Hold]>) {
        guard case .corrupt(let moved) = result else {
            Issue.record("expected .corrupt, got \(result)")
            return
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(moved.map { FileManager.default.fileExists(atPath: $0.path) } == true)
        #expect(moved?.lastPathComponent.hasPrefix("holds.corrupt-") == true)
    }

    @Test func missingFileLoadsAsMissing() {
        guard case .missing = store.load() else { Issue.record("expected .missing"); return }
    }

    @Test func roundTripsHolds() throws {
        let holds = [makeHold(label: "A"), makeHold(label: "B", end: .deadline(referenceDate))]
        try store.save(holds)
        guard case .loaded(let loaded) = store.load() else { Issue.record("expected .loaded"); return }
        #expect(loaded == holds)
    }

    @Test func corruptFileIsMovedAside() throws {
        try write("this is not json")
        assertMovedAside(store.load(now: referenceDate))
    }

    @Test func truncatedFileIsMovedAside() throws {
        try store.save([makeHold()])
        let data = try Data(contentsOf: url)
        try data.prefix(data.count / 2).write(to: url)
        assertMovedAside(store.load(now: referenceDate))
    }

    @Test func futureSchemaIsMovedAside() throws {
        try JSONFileStore<[Hold]>(url: url, schemaVersion: 99).save([makeHold()])
        assertMovedAside(store.load(now: referenceDate))
    }

    @Test func oversizedFileIsMovedAside() throws {
        try write(String(repeating: " ", count: JSONFileStore<[Hold]>.maxFileSize + 1))
        assertMovedAside(store.load(now: referenceDate))
    }

    @Test func restoreRules() {
        let now = referenceDate
        let inspector = FakeInspector()
        let alive = ProcessIdentity(pid: 10, startTime: 1)
        inspector.identities[10] = alive
        inspector.identities[11] = ProcessIdentity(pid: 11, startTime: 999)

        let keepIndefinite = makeHold(end: .indefinite)
        let keepFuture = makeHold(end: .deadline(now.addingTimeInterval(60)))
        let keepInGrace = makeHold(end: .deadline(now.addingTimeInterval(-30)), grace: 60)
        let dropPast = makeHold(end: .deadline(now.addingTimeInterval(-1)))
        let keepAlive = makeHold(end: .processExit(alive))
        let dropRecycled = makeHold(end: .processExit(ProcessIdentity(pid: 11, startTime: 1)))
        let dropGone = makeHold(end: .processExit(ProcessIdentity(pid: 12, startTime: 1)))
        let dropTrigger = makeHold(end: .triggerControlled, source: .trigger(UUID()))

        let restored = HoldRestorer.restorable(
            [keepIndefinite, keepFuture, keepInGrace, dropPast, keepAlive, dropRecycled, dropGone, dropTrigger],
            now: now, inspector: inspector
        )
        #expect(restored.map(\.id) == [keepIndefinite.id, keepFuture.id, keepInGrace.id, keepAlive.id])
    }
}
