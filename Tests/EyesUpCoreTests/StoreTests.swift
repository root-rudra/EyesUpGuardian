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

    @Test func restoreDropsHoldsOutsideCreationLimits() {
        let now = referenceDate
        let absurd = makeHold(end: .deadline(Date(timeIntervalSinceReferenceDate: 1e300)))
        let tenYears = makeHold(end: .deadline(now.addingTimeInterval(10 * 365 * 86_400)))
        let hugeGrace = makeHold(end: .deadline(now.addingTimeInterval(60)), grace: 1e12)
        let negativeGrace = makeHold(end: .deadline(now.addingTimeInterval(60)), grace: -5)
        let longLabel = makeHold(label: String(repeating: "x", count: 500))
        let unknownPolicyOnly = makeHold(policy: SleepPolicy(rawValue: 1 << 10))
        let triggerSourced = makeHold(end: .indefinite, source: .trigger(UUID()))
        let fine = makeHold(end: .deadline(now.addingTimeInterval(3600)), grace: 300)

        let restored = HoldRestorer.restorable(
            [absurd, tenYears, hugeGrace, negativeGrace, longLabel, unknownPolicyOnly, triggerSourced, fine],
            now: now, inspector: FakeInspector()
        )
        #expect(restored.map(\.id) == [fine.id])
    }

    @Test func restoreMasksUnknownPolicyBits() {
        let hold = makeHold(policy: SleepPolicy(rawValue: SleepPolicy.system.rawValue | 1 << 10))
        let restored = HoldRestorer.restorable([hold], now: referenceDate, inspector: FakeInspector())
        #expect(restored.first?.policy == .system)
    }

    @Test func restoreDropsHoldsCreatedInTheFuture() {
        // A far-future createdAt would push `createdAt + safetyCap` out of reach, so the cap never bites.
        let hold = makeHold(end: .indefinite, createdAt: referenceDate.addingTimeInterval(7 * 86_400))
        #expect(HoldRestorer.sanitized(hold, now: referenceDate) == nil)
        #expect(HoldRestorer.sanitized(makeHold(end: .indefinite, createdAt: referenceDate.addingTimeInterval(30)), now: referenceDate) != nil)
    }

    @Test func restoreCapsTheNumberOfHolds() {
        let many = (0..<(HoldRestorer.maxHolds + 50)).map { makeHold(label: "Hold \($0)") }
        let restored = HoldRestorer.restorable(many, now: referenceDate, inspector: FakeInspector())
        #expect(restored.count == HoldRestorer.maxHolds)
    }

    // MARK: Hostile files (security audit)

    @Test func aSymlinkIsNeverFollowed() throws {
        // A symlink reports its own tiny size to stat, so a size check alone lets an attacker
        // point the store at any file the user can read — or at a FIFO, which hangs the read.
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let secret = directory.appendingPathComponent("secret.txt")
        try Data(String(repeating: "S", count: 5000).utf8).write(to: secret)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: secret)

        let result = store.load(now: referenceDate)
        guard case .corrupt = result else {
            Issue.record("a symlink must be refused, got \(result)")
            return
        }
        // The target itself must be untouched.
        #expect(try Data(contentsOf: secret).count == 5000)
    }

    @Test func aDirectoryInPlaceOfTheFileIsRefused() throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        guard case .corrupt = store.load(now: referenceDate) else {
            Issue.record("a directory must be refused")
            return
        }
    }

    @Test func savedFilesAreReadableOnlyByTheUser() throws {
        try store.save([makeHold()])
        let fileMode = try #require(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)
        let directoryMode = try #require(FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber)
        #expect(fileMode.int16Value == 0o600)
        #expect(directoryMode.int16Value == 0o700)
    }

    @Test func corruptFilesDoNotPileUpForever() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for index in 0..<6 {
            try Data("nonsense".utf8).write(to: url)
            _ = store.load(now: referenceDate.addingTimeInterval(Double(index) * 60))
        }
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.contains(".corrupt-") }
        #expect(leftovers.count <= JSONFileStore<[Hold]>.keptCorruptFiles)
    }

    @Test func restoreRefusesShapesTheAppCannotCreate() {
        // A link's session always has an end; a saved "Automation" hold with none did not come from us.
        let endless = makeHold(end: .indefinite, source: .automation)
        #expect(HoldRestorer.sanitized(endless, now: referenceDate) == nil)

        // And a link's session can never run longer than the link cap.
        let tooLong = makeHold(end: .deadline(referenceDate.addingTimeInterval(72 * 3600)), source: .automation)
        let clamped = HoldRestorer.sanitized(tooLong, now: referenceDate)
        #expect(clamped?.effectiveDeadline == referenceDate.addingTimeInterval(AutomationParser.maxDuration))
    }
    @Test func twoCorruptFilesInTheSameSecondBothSurvive() throws {
        try write("nonsense")
        _ = store.load(now: referenceDate)
        try write("more nonsense")
        _ = store.load(now: referenceDate) // same instant
        let copies = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.contains(".corrupt-") }
        #expect(copies.count == 2)
    }
    /// A file written by an older version is not corrupt: throwing it away would cost the user 90
    /// days of history the first time any schema version is bumped.
    @Test func anOlderSchemaVersionIsReadRatherThanDiscarded() throws {
        try write(#"{"schemaVersion":1,"value":[]}"#)
        let newerStore = JSONFileStore<[Hold]>(url: url, schemaVersion: 2)
        guard case .loaded(let holds) = newerStore.load(now: referenceDate) else {
            Issue.record("expected .loaded from an older file")
            return
        }
        #expect(holds.isEmpty)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    /// A file from a *newer* version may use shapes this build doesn't understand, so it is moved
    /// aside rather than half-read.
    @Test func aNewerSchemaVersionIsStillMovedAside() throws {
        try write(#"{"schemaVersion":9,"value":[]}"#)
        assertMovedAside(store.load(now: referenceDate))
    }
}
