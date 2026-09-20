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
        // Fed a fixed list: a real EyesUpGuardian running on this Mac is a different process
        // holding its own assertion, and the probe is right to list that one.
        let mine = SystemAssertion(pid: 4242, type: AssertionKind.preventIdleSystemSleep.ioKitType, name: "mine")
        let theirs = SystemAssertion(pid: 4243, type: AssertionKind.preventIdleSystemSleep.ioKitType, name: "theirs")
        let probe = AssertionProbe(ownPID: 4242, source: { [mine, theirs] })
        let others = probe.sample() ?? []
        #expect(others.count == 1)
        #expect(others.first?.processName == "process 4243")
    }

    @Test func processEntriesCarryTheIdentityTheyWereSampledWith() throws {
        // Without this, the UI can only re-derive an identity at click time, which makes the
        // recycled-PID check compare a process against itself.
        let inspector = FakeInspector()
        let clock = FakeClock()
        let identity = ProcessIdentity(pid: 7, startTime: 4242)
        inspector.allPIDs = [7]
        inspector.identities[7] = identity
        inspector.details[7] = ProcessDetails(name: "builder", cpuSeconds: 0, memoryBytes: 10, threads: 1,
                                              uid: 501, identity: identity)
        let probe = ProcessProbe(inspector: inspector, clock: clock, ownUID: 501)
        _ = probe.sample()
        clock.advance(1)
        let entry = try #require(probe.sample()?.first)
        #expect(entry.identity == identity)
    }

    @Test func namesFromOtherProcessesCannotSpoofTheUI() throws {
        let inspector = FakeInspector()
        let clock = FakeClock()
        let nasty = "evil\u{202E}gnp.exe\nPID 1 launchd" + String(repeating: "x", count: 200)
        let identity = ProcessIdentity(pid: 9, startTime: 1)
        inspector.allPIDs = [9]
        inspector.identities[9] = identity
        inspector.details[9] = ProcessDetails(name: nasty, cpuSeconds: 0, memoryBytes: 1, threads: 1,
                                              uid: 501, identity: identity)
        let probe = ProcessProbe(inspector: inspector, clock: clock, ownUID: 501)
        _ = probe.sample()
        clock.advance(1)
        let entry = try #require(probe.sample()?.first)
        #expect(!entry.name.contains("\n"))
        #expect(!entry.name.unicodeScalars.contains { $0.properties.generalCategory == .format })
        #expect(entry.name.count <= ProcessProbe.maxNameLength)
    }

    @Test func aRefusedSignalIsReported() {
        let inspector = FakeInspector()
        let identity = ProcessIdentity(pid: 4242, startTime: 100)
        inspector.identities[4242] = identity
        inspector.owners[4242] = 501
        let signaller = FakeSignaller()
        signaller.succeeds = false
        let control = ProcessControl(inspector: inspector, ownUID: 501, signaller: signaller)
        #expect(throws: ProcessControlError.signalRefused) { try control.quit(identity, force: false) }
    }

    @Test func cpuTicksReadAsUnsigned() {
        // Kernel tick counters are unsigned 32-bit; after ~250 days of uptime they read negative as Int32.
        #expect(CPUProbe.unsignedTick(-1) == UInt64(UInt32.max))
        #expect(CPUProbe.unsignedTick(Int32.min) == UInt64(UInt32(Int32.max) + 1))
        #expect(CPUProbe.unsignedTick(1234) == 1234)
    }
}
