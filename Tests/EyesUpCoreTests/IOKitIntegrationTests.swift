import Foundation
import Testing
@testable import EyesUpCore

@Suite(.integration, .serialized) @MainActor struct IOKitIntegrationTests {
    private func ownAssertionNames() -> [String] {
        SystemAssertions.forProcess(getpid()).map(\.name)
    }

    @Test func createRenameRelease() throws {
        let provider = IOKitPowerAssertions()
        let id = try provider.create(.preventIdleSystemSleep, name: "EyesUpGuardian-test-A")
        #expect(SystemAssertions.forProcess(getpid()).contains {
            $0.name == "EyesUpGuardian-test-A" && $0.type == "PreventUserIdleSystemSleep"
        })

        provider.rename(id, to: "EyesUpGuardian-test-B")
        #expect(ownAssertionNames().contains("EyesUpGuardian-test-B"))

        provider.release(id)
        #expect(!ownAssertionNames().contains("EyesUpGuardian-test-B"))
    }

    @Test func engineHoldsAndReleasesRealAssertions() {
        let engine = AwakeEngine(provider: IOKitPowerAssertions())
        engine.reconcile(holds: [makeHold(label: "integration", policy: [.system, .display])])
        let assertions = SystemAssertions.forProcess(getpid())
        #expect(Set(assertions.map(\.type)).isSuperset(of: ["PreventUserIdleSystemSleep", "PreventUserIdleDisplaySleep"]))
        #expect(assertions.allSatisfy { $0.name == "EyesUpGuardian: integration" })

        engine.releaseAll()
        #expect(SystemAssertions.forProcess(getpid()).isEmpty)
    }

    @Test func declaringUserActivityDoesNotThrowOrLeak() async throws {
        IOKitPowerAssertions().declareUserActivity(name: "EyesUpGuardian-test-nudge")
        try await Task.sleep(for: .seconds(6))
        #expect(!ownAssertionNames().contains("EyesUpGuardian-test-nudge"))
    }
}
