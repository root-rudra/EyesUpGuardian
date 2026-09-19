import EyesUpCore
import Foundation
import Testing
@testable import EyesUpApp

@Suite @MainActor struct StatViewModelTests {
    private func makeCenter() -> MetricsCenter {
        MetricsCenter(probes: StubProbes(), executor: InlineExecutor(), scheduler: DispatchTimerScheduler())
    }

    @Test func startSubscribesAndStopReleases() {
        let center = makeCenter()
        let model = StatsViewModel(center: center, ids: [.cpu, .memory], interval: 1)
        #expect(!center.isSampling)

        model.start()
        #expect(center.isSampling)

        model.stop()
        #expect(!center.isSampling)
    }

    @Test func startingTwiceKeepsOneSubscription() {
        let center = makeCenter()
        let model = StatsViewModel(center: center, ids: [.cpu], interval: 1)
        model.start()
        model.start()
        model.stop()
        #expect(!center.isSampling) // a leaked second subscription would keep it sampling
    }

    @Test func tilesShowValuesWhenPresentAndDashesWhenNot() {
        let center = makeCenter()
        let model = StatsViewModel(center: center, ids: [.cpu, .memory, .power, .system], interval: 1)
        model.start()
        let titles = model.tiles.map(\.title)
        #expect(titles == ["CPU", "Memory", "Power", "Uptime"])
        #expect(model.tiles[0].value == "20%")
        #expect(model.tiles[2].value == StatFormatting.unavailable) // StubProbes reports no power
        model.stop()
    }
}

/// Minimal probes for app-side tests: CPU, memory and uptime answer; power never does.
final class StubProbes: MetricsProbing, @unchecked Sendable {
    func sample(_ ids: Set<MetricID>) -> MetricsSnapshot {
        var snapshot = MetricsSnapshot()
        if ids.contains(.cpu) { snapshot.cpu = CPUMetrics(total: 20, cores: [20], performance: nil, efficiency: nil) }
        if ids.contains(.memory) {
            snapshot.memory = MemoryMetrics(usedBytes: 40_000_000_000, appBytes: 20_000_000_000,
                                            wiredBytes: 10_000_000_000, compressedBytes: 0,
                                            totalBytes: 256_000_000_000, swapUsedBytes: 0, pressure: .normal)
        }
        if ids.contains(.system) {
            snapshot.system = SystemMetrics(bootTime: Date().addingTimeInterval(-90_000), loadAverage: (1, 1, 1),
                                            idleSeconds: 3, thermal: .nominal)
        }
        return snapshot
    }

    func resetBaselines() {}
}
