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
}
