import Foundation
import Testing
@testable import EyesUpCore

@Suite struct LiveSystemSourcesTests {
    @Test func cpuTicksIncrease() async throws {
        let counters = LiveSystemCounters()
        let first = try #require(counters.cpuTicks())
        try await Task.sleep(for: .milliseconds(200))
        let second = try #require(counters.cpuTicks())
        #expect(second.total > first.total)
        #expect(second.busy >= first.busy)
        #expect(second.busy <= second.total)
    }

    @Test func networkAndDiskCountersAreReadable() async throws {
        let counters = LiveSystemCounters()
        let network = try #require(counters.networkBytes())
        let disk = try #require(counters.diskBytesWritten())
        try await Task.sleep(for: .milliseconds(200))
        #expect(try #require(counters.networkBytes()) >= network)
        #expect(try #require(counters.diskBytesWritten()) >= disk)
    }

    @Test func processListerSeesThisTestProcess() {
        let names = LiveProcessLister().runningProcessNames()
        #expect(!names.isEmpty)
        let own = ProcessInfo.processInfo.processName
        #expect(names.contains { $0.caseInsensitiveCompare(own) == .orderedSame })
    }

    @Test @MainActor func thermalLevelIsReadable() {
        #expect(ThermalLevel.allCases.contains(LiveThermalMonitor().currentLevel()))
    }

    @Test(.integration) @MainActor func displaysAndPowerAreReadableOnThisMac() {
        #expect(!LiveDisplayInventory().connectedDisplays().isEmpty)
        #expect(LivePowerSourceInfo().isOnACPower()) // Mac Studio is always on AC
    }
}
