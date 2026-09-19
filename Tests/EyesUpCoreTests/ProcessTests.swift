import Foundation
import Testing
@testable import EyesUpCore

@Suite @MainActor struct ProcessTests {
    /// Polls while yielding the main actor, so main-queue callbacks can run.
    private func waitUntil(timeout: Duration = .seconds(3), _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func spawnSleep(_ seconds: String) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = [seconds]
        try process.run()
        return process
    }

    @Test func inspectorIdentifiesOwnProcessStably() {
        let inspector = LibprocInspector()
        let first = inspector.identity(of: getpid())
        #expect(first != nil)
        #expect(first == inspector.identity(of: getpid()))
        #expect(inspector.name(of: getpid())?.isEmpty == false)
    }

    @Test(arguments: [Int32(0), -1, Int32.max])
    func inspectorRejectsImpossiblePIDs(pid: Int32) {
        #expect(LibprocInspector().identity(of: pid) == nil)
        #expect(LibprocInspector().name(of: pid) == nil)
    }

    @Test func inspectorNamesAChildProcess() throws {
        let child = try spawnSleep("5")
        defer { child.terminate() }
        #expect(LibprocInspector().name(of: child.processIdentifier) == "sleep")
    }

    @Test func watcherFiresWhenProcessExits() async throws {
        let child = try spawnSleep("0.2")
        let inspector = LibprocInspector()
        let identity = try #require(inspector.identity(of: child.processIdentifier))
        var fired = false
        let task = KqueueExitWatcher(inspector: inspector).watch(identity) { fired = true }
        try await waitUntil { fired }
        #expect(fired)
        task.cancel()
    }

    @Test func watcherFiresForAlreadyExitedProcess() async throws {
        let child = try spawnSleep("0.2")
        let inspector = LibprocInspector()
        let identity = try #require(inspector.identity(of: child.processIdentifier))
        child.waitUntilExit()
        var fired = false
        let task = KqueueExitWatcher(inspector: inspector).watch(identity) { fired = true }
        try await waitUntil { fired }
        #expect(fired)
        task.cancel()
    }

    @Test func watcherTreatsRecycledPIDAsExited() async throws {
        // Our own PID is alive, but with a different start time it stands in for a recycled PID.
        let fake = FakeInspector()
        fake.identities[getpid()] = ProcessIdentity(pid: getpid(), startTime: 999)
        var fired = false
        let task = KqueueExitWatcher(inspector: fake).watch(ProcessIdentity(pid: getpid(), startTime: 1)) { fired = true }
        try await waitUntil { fired }
        #expect(fired)
        task.cancel()
    }

    @Test func cancelledWatchDoesNotFire() async throws {
        let child = try spawnSleep("0.3")
        let inspector = LibprocInspector()
        let identity = try #require(inspector.identity(of: child.processIdentifier))
        var fired = false
        let task = KqueueExitWatcher(inspector: inspector).watch(identity) { fired = true }
        task.cancel()
        child.waitUntilExit()
        try await Task.sleep(for: .milliseconds(300))
        #expect(!fired)
    }
}
