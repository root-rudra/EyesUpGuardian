import Testing
@testable import EyesUpCore

@Suite @MainActor struct AwakeEngineTests {
    let provider = FakePowerAssertions()

    @Test func singleHoldTakesOneNamedAssertion() {
        let engine = AwakeEngine(provider: provider)
        engine.reconcile(holds: [makeHold(label: "Timer 2h")])
        #expect(provider.liveKinds == [.preventIdleSystemSleep])
        #expect(provider.liveNames == ["EyesUpGuardian: Timer 2h"])
    }

    @Test func overlappingHoldsShareOneAssertionPerKind() {
        let engine = AwakeEngine(provider: provider)
        engine.reconcile(holds: [makeHold(label: "Timer 2h"), makeHold(label: "Claude running")])
        #expect(provider.live.count == 1)
        #expect(provider.liveNames == ["EyesUpGuardian: Timer 2h · Claude running"])
    }

    @Test func addingDisplayPolicyAddsOnlyTheDisplayAssertion() {
        let engine = AwakeEngine(provider: provider)
        let timer = makeHold(label: "Timer 2h")
        engine.reconcile(holds: [timer])
        engine.reconcile(holds: [timer, makeHold(label: "Movie", policy: [.system, .display])])
        #expect(provider.liveKinds == [.preventIdleSystemSleep, .preventDisplaySleep])
        #expect(provider.createCount == 2)
    }

    @Test func removingOneOfTwoHoldsKeepsAssertion() {
        let engine = AwakeEngine(provider: provider)
        let a = makeHold(label: "A")
        let b = makeHold(label: "B")
        engine.reconcile(holds: [a, b])
        engine.reconcile(holds: [b])
        #expect(provider.liveKinds == [.preventIdleSystemSleep])
        #expect(provider.createCount == 1)
        #expect(provider.liveNames == ["EyesUpGuardian: B"])
    }

    @Test func noHoldsReleasesEverything() {
        let engine = AwakeEngine(provider: provider)
        engine.reconcile(holds: [makeHold(policy: [.system, .display, .disk, .systemOnAC])])
        #expect(provider.live.count == 4)
        engine.releaseAll()
        #expect(provider.live.isEmpty)
        #expect(engine.active.isEmpty)
    }

    @Test func longNamesAreTruncated() {
        let holds = (0..<40).map { makeHold(label: "Very long reason number \($0)") }
        let name = AwakeEngine.assertionName(for: holds)
        #expect(name.count == AwakeEngine.maxNameLength)
        #expect(name.hasPrefix("EyesUpGuardian: "))
        #expect(name.hasSuffix("…"))
    }

    @Test func failureIsReportedAndRetriedOnNextReconcile() {
        let engine = AwakeEngine(provider: provider)
        provider.failingKinds = [.preventDisplaySleep]
        let hold = makeHold(policy: [.system, .display])
        engine.reconcile(holds: [hold])
        #expect(engine.lastError?.kind == .preventDisplaySleep)
        #expect(provider.liveKinds == [.preventIdleSystemSleep])

        provider.failingKinds = []
        engine.reconcile(holds: [hold])
        #expect(engine.lastError == nil)
        #expect(provider.liveKinds == [.preventIdleSystemSleep, .preventDisplaySleep])
    }

    @Test func assertionNamesStayPrintable() {
        // "Until 8:15 PM" as macOS formats it, with U+202F before PM.
        let hold = makeHold(label: "Until 8:15\u{202F}PM")
        let name = AwakeEngine.assertionName(for: [hold])
        #expect(name == "EyesUpGuardian: Until 8:15 PM")
        #expect(name.allSatisfy { $0.isASCII })
    }

    @Test func aNameChangeKeepsOneLiveAssertion() {
        let engine = AwakeEngine(provider: provider)
        engine.reconcile(holds: [makeHold(label: "Timer 2h")])
        engine.reconcile(holds: [makeHold(label: "Until 8:15\u{202F}PM")])
        #expect(provider.live.count == 1)
        #expect(provider.liveNames == ["EyesUpGuardian: Until 8:15 PM"])
    }
}
