import Foundation
import Testing
@testable import EyesUpCore

/// These read the real machine, so they assert ranges and relationships, never exact values.
@Suite struct ProbeTests {
    @Test func cpuProbeNeedsTwoSamplesThenReportsSanePercentages() async throws {
        let probe = CPUProbe()
        #expect(probe.sample() == nil) // first call only sets a baseline
        try await Task.sleep(for: .milliseconds(200))
        let metrics = try #require(probe.sample())
        #expect(metrics.total >= 0 && metrics.total <= 100)
        #expect(metrics.cores.count == ProcessInfo.processInfo.processorCount)
        #expect(metrics.cores.allSatisfy { $0 >= 0 && $0 <= 100 })
        if let performance = metrics.performance, let efficiency = metrics.efficiency {
            #expect(performance >= 0 && performance <= 100)
            #expect(efficiency >= 0 && efficiency <= 100)
        }
    }

    @Test func memoryTotalsAreConsistent() throws {
        let metrics = try #require(MemoryProbe().sample())
        #expect(metrics.totalBytes > 0)
        #expect(metrics.usedBytes > 0)
        #expect(metrics.usedBytes <= metrics.totalBytes)
        #expect(metrics.wiredBytes <= metrics.usedBytes)
        #expect(metrics.totalBytes == ProcessInfo.processInfo.physicalMemory)
        #expect([.normal, .warning, .critical].contains(metrics.pressure))
    }

    @Test func systemProbeReportsBootTimeLoadAndIdle() throws {
        let metrics = try #require(SystemProbe().sample())
        #expect(metrics.bootTime < Date())
        #expect(metrics.bootTime > Date(timeIntervalSince1970: 1_000_000_000))
        #expect(metrics.loadAverage.0 >= 0)
        #expect(metrics.idleSeconds >= 0)
        #expect(ThermalLevel.allCases.contains(metrics.thermal))
    }

    @Test func storageProbeReportsSpaceImmediatelyAndRatesAfterTwoSamples() {
        let probe = StorageProbe()
        let first = probe.sample()
        #expect(first?.totalBytes ?? 0 > 0)
        #expect((first?.freeBytes ?? 0) <= (first?.totalBytes ?? 0))
        #expect(first?.readBytesPerSecond == nil) // no interval yet

        let second = probe.sample()
        #expect((second?.readBytesPerSecond ?? 0) >= 0)
        #expect((second?.writeBytesPerSecond ?? 0) >= 0)
    }

    @Test func networkProbeReportsRatesAfterTwoSamples() {
        let probe = NetworkProbe()
        #expect(probe.sample()?.inBytesPerSecond == nil)
        let second = probe.sample()
        #expect((second?.inBytesPerSecond ?? 0) >= 0)
        #expect((second?.outBytesPerSecond ?? 0) >= 0)
    }

    @Test func ratesResetAfterWake() {
        // The Mac slept for an hour: counters jumped, but that isn't a rate.
        let counters = FakeCounters()
        let clock = FakeClock()
        counters.network = 1000
        counters.disk = 1000
        let network = NetworkProbe(counters: counters, clock: clock)
        let storage = StorageProbe(counters: counters, clock: clock)
        _ = network.sample()
        _ = storage.sample()

        counters.network = 50_000_000_000
        counters.disk = 50_000_000_000
        clock.advance(3600)
        network.resetBaseline()
        storage.resetBaseline()
        #expect(network.sample()?.inBytesPerSecond == nil)
        #expect(storage.sample()?.readBytesPerSecond == nil)
    }
}
