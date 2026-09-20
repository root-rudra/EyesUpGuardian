import Foundation
import Testing
@testable import EyesUpApp
@testable import EyesUpCore

@Suite @MainActor struct DashboardSamplingTests {
    private func makeCenter() -> MetricsCenter {
        MetricsCenter(probes: StubProbes(), executor: InlineExecutor(), scheduler: DispatchTimerScheduler())
    }

    /// Regression: Overview gained a second, slower subscription, and the window's stop path still
    /// named the models one by one — so closing or minimising the dashboard left the expensive
    /// probes (GPU, disk, sensors) sampling every five seconds with nothing on screen.
    @Test func closingTheWindowStopsEveryClaimItHolds() {
        let center = makeCenter()
        let state = DashboardState()
        state.overviewStats = StatsViewModel(center: center, ids: [.cpu, .memory], interval: 1)
        state.overviewSlowStats = StatsViewModel(center: center, ids: [.gpu, .storage], interval: 5)
        state.processesStats = StatsViewModel(center: center, ids: [.processes], interval: 5)

        for model in state.sampling { model.start() }
        #expect(center.isSampling)

        for model in state.sampling { model.stop() }
        #expect(!center.isSampling, "a claim the window holds was never stopped")
    }

    @Test func showingATabStartsWhatThatTabNeeds() {
        let center = makeCenter()
        let state = DashboardState()
        state.overviewStats = StatsViewModel(center: center, ids: [.cpu], interval: 1)
        state.overviewSlowStats = StatsViewModel(center: center, ids: [.gpu], interval: 5)
        state.processesStats = StatsViewModel(center: center, ids: [.processes], interval: 5)

        #expect(state.sampling(for: .overview).count == 2) // both halves of Overview, fast and slow
        #expect(state.sampling(for: .processes).count == 1)
        #expect(state.sampling(for: .settings).isEmpty)
        // Nothing the window holds may be missing from the stop list.
        #expect(Set(DashboardState.Tab.allCases.flatMap { state.sampling(for: $0) }.map(ObjectIdentifier.init))
                .isSubset(of: Set(state.sampling.map(ObjectIdentifier.init))))
    }
}
