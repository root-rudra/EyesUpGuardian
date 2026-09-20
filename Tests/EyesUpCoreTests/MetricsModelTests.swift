import Foundation
import Testing
@testable import EyesUpCore

@Suite struct MetricsModelTests {
    @Test func anEmptySnapshotOffersNothing() {
        let snapshot = MetricsSnapshot()
        #expect(snapshot.availableIDs.isEmpty)
        #expect(snapshot.cpu == nil)
    }

    @Test func availabilityFollowsWhatIsPresent() {
        var snapshot = MetricsSnapshot()
        snapshot.cpu = CPUMetrics(total: 12, cores: [10, 14], performance: 14, efficiency: 10)
        snapshot.power = PowerMetrics(watts: 38)
        #expect(snapshot.availableIDs == [.cpu, .power])
    }

    @Test func mergingKeepsTheNewerReadingAndTheOlderRest() {
        var older = MetricsSnapshot()
        older.cpu = CPUMetrics(total: 12, cores: [12], performance: nil, efficiency: nil)
        older.power = PowerMetrics(watts: 20)
        var newer = MetricsSnapshot()
        newer.cpu = CPUMetrics(total: 80, cores: [80], performance: nil, efficiency: nil)

        let merged = older.merging(newer)
        #expect(merged.cpu?.total == 80)     // newer wins
        #expect(merged.power?.watts == 20)   // older survives where newer says nothing
        #expect(merged.availableIDs == [.cpu, .power])
    }

    @Test func everyMetricIDHasASlot() {
        // A new MetricID with no snapshot slot would sample but never display.
        var snapshot = MetricsSnapshot()
        snapshot.cpu = CPUMetrics(total: 0, cores: [], performance: nil, efficiency: nil)
        snapshot.memory = MemoryMetrics(usedBytes: 1, appBytes: 1, wiredBytes: 1, compressedBytes: 0,
                                        totalBytes: 2, swapUsedBytes: 0, pressure: .normal)
        snapshot.system = SystemMetrics(bootTime: referenceDate, loadAverage: (1, 1, 1), idleSeconds: 0, thermal: .nominal)
        snapshot.storage = StorageMetrics(freeBytes: 1, totalBytes: 2, readBytesPerSecond: nil, writeBytesPerSecond: nil)
        snapshot.network = NetworkMetrics(inBytesPerSecond: nil, outBytesPerSecond: nil)
        snapshot.processes = [ProcessEntry(pid: 1, identity: ProcessIdentity(pid: 1, startTime: 1), name: "a",
                                           cpuPercent: 0, memoryBytes: 0, threads: 1, isOwn: false)]
        snapshot.power = PowerMetrics(watts: 1)
        snapshot.fans = FanMetrics(fans: [FanReading(index: 0, rpm: 1000, maxRPM: 3000)])
        snapshot.temperature = TemperatureMetrics(celsius: 40, sensorCount: 3)
        snapshot.gpu = GPUMetrics(utilization: 5)
        snapshot.otherAssertions = [OtherAssertion(processName: "Zoom", type: "PreventUserIdleDisplaySleep")]
        #expect(snapshot.availableIDs == Set(MetricID.allCases))
    }
}
