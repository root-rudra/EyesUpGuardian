import Foundation
import Testing
@testable import EyesUpCore

@Suite struct ProcessControlTests {
    private let mine = ProcessIdentity(pid: 4242, startTime: 100)

    private func inspector(uid: uid_t, identity: ProcessIdentity?) -> FakeInspector {
        let inspector = FakeInspector()
        if let identity {
            inspector.identities[identity.pid] = identity
            inspector.owners[identity.pid] = uid
            inspector.names[identity.pid] = "victim"
        }
        return inspector
    }

    @Test func quitsYourOwnProcess() throws {
        let signaller = FakeSignaller()
        let control = ProcessControl(inspector: inspector(uid: 501, identity: mine), ownUID: 501, signaller: signaller)
        try control.quit(mine, force: false)
        #expect(signaller.sent.count == 1)
        #expect(signaller.sent.first?.0 == SIGTERM)
        #expect(signaller.sent.first?.1 == 4242)

        try control.quit(mine, force: true)
        #expect(signaller.sent.last?.0 == SIGKILL)
    }

    @Test func refusesToQuitAnotherUsersProcess() {
        let signaller = FakeSignaller()
        let control = ProcessControl(inspector: inspector(uid: 0, identity: mine), ownUID: 501, signaller: signaller)
        #expect(throws: ProcessControlError.notYours) { try control.quit(mine, force: false) }
        #expect(signaller.sent.isEmpty)
    }

    @Test func refusesWhenTheProcessIsGone() {
        let signaller = FakeSignaller()
        let control = ProcessControl(inspector: inspector(uid: 501, identity: nil), ownUID: 501, signaller: signaller)
        #expect(throws: ProcessControlError.gone) { try control.quit(mine, force: false) }
        #expect(signaller.sent.isEmpty)
    }

    @Test func refusesWhenThePIDWasRecycled() {
        // Same PID, different start time: a different process now owns that number.
        let signaller = FakeSignaller()
        let recycled = ProcessIdentity(pid: 4242, startTime: 999)
        let control = ProcessControl(inspector: inspector(uid: 501, identity: recycled), ownUID: 501, signaller: signaller)
        #expect(throws: ProcessControlError.recycled) { try control.quit(mine, force: false) }
        #expect(signaller.sent.isEmpty)
    }

    @Test func processProbeRanksByCPUAndMarksYourOwn() throws {
        let inspector = FakeInspector()
        let clock = FakeClock()
        for (pid, cpu, uid) in [(Int32(1), 10.0, uid_t(0)), (2, 50.0, 501), (3, 5.0, 501)] {
            inspector.identities[pid] = ProcessIdentity(pid: pid, startTime: 1)
            inspector.details[pid] = ProcessDetails(name: "p\(pid)", cpuSeconds: 0, memoryBytes: UInt64(pid) * 1000,
                                                    threads: 2, uid: uid, identity: ProcessIdentity(pid: pid, startTime: 1))
            inspector.cpuSecondsByPID[pid] = cpu
        }
        inspector.allPIDs = [1, 2, 3]
        let probe = ProcessProbe(inspector: inspector, clock: clock, ownUID: 501)
        #expect(probe.sample()?.isEmpty == true) // first pass is a baseline

        clock.advance(1)
        for pid in [Int32(1), 2, 3] { inspector.cpuSecondsByPID[pid, default: 0] += Double(pid) * 0.1 }
        let entries = try #require(probe.sample())
        #expect(entries.map(\.pid) == [3, 2, 1]) // highest CPU first
        #expect(entries.first { $0.pid == 1 }?.isOwn == false)
        #expect(entries.first { $0.pid == 2 }?.isOwn == true)
    }

    @Test func assertionProbeExcludesOurOwnHolds() {
        let probe = AssertionProbe(ownPID: getpid())
        let others = probe.sample() ?? []
        #expect(!others.contains { $0.processName == "EyesUpGuardian" })
    }
}
