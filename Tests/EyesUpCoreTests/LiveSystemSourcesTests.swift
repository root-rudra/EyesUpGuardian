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

    @Test @MainActor func severalObserversCoexistAndCancelIndependently() {
        // Two "on AC power" triggers share one LivePowerSourceInfo. Each registration must keep its own
        // callback box alive: freeing one while IOKit still points at it is a use-after-free.
        let power = LivePowerSourceInfo()
        let first = power.observeChanges {}
        let second = power.observeChanges {}
        #expect(power.activeObservationCount == 2)
        first.cancel()
        #expect(power.activeObservationCount == 1)
        second.cancel()
        #expect(power.activeObservationCount == 0)
    }

    @Test @MainActor func severalDisplayObserversCoexistAndCancelIndependently() {
        let displays = LiveDisplayInventory()
        let first = displays.observeChanges {}
        let second = displays.observeChanges {}
        #expect(displays.activeObservationCount == 2)
        first.cancel()
        #expect(displays.activeObservationCount == 1)
        second.cancel()
        #expect(displays.activeObservationCount == 0)
    }
}
