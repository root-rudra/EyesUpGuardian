import Foundation
import Testing
@testable import EyesUpCore

@Suite struct SMCProbeTests {
    @Test(.integration) func gpuUtilizationIsAPercentage() throws {
        let metrics = try #require(GPUProbe().sample())
        #expect(metrics.utilization >= 0 && metrics.utilization <= 100)
    }

    @Test(.integration) func smcReportsPowerFansAndTemperatureOnThisMac() throws {
        let smc = try #require(SMC())
        defer { smc.close() }
        let probe = SMCProbe(smc: smc)
        #expect(probe.isAvailable)

        let power = try #require(probe.power())
        #expect(power.watts > 1 && power.watts < 1000) // a Mac Studio idles near 20 W

        let fans = try #require(probe.fans())
        #expect(!fans.fans.isEmpty)
        #expect(fans.fans.allSatisfy { $0.rpm >= 0 && $0.rpm < 20_000 })

        let temperature = try #require(probe.temperature())
        #expect(temperature.celsius > 5 && temperature.celsius < 120)
        #expect(temperature.sensorCount > 0)
    }

    @Test func unavailableKeysAreDroppedOnce() {
        // A probe whose keys never answer must stay quiet rather than retry every sample.
        let smc = FakeSMC(values: [:])
        let probe = SMCProbe(smc: smc)
        #expect(probe.power() == nil)
        #expect(probe.fans() == nil)
        #expect(probe.temperature() == nil)
        #expect(!probe.isAvailable)
        let readsAfterFirstRound = smc.readCount
        _ = probe.power()
        _ = probe.temperature()
        #expect(smc.readCount == readsAfterFirstRound) // curated list probed once, then remembered
    }

    @Test func temperatureIsTheHottestReadableSensor() {
        let smc = FakeSMC(values: ["Tp0T": 41.5, "Tp1T": 58.25, "Te05": 30])
        let probe = SMCProbe(smc: smc)
        let temperature = probe.temperature()
        #expect(temperature?.celsius == 58.25)
        #expect(temperature?.sensorCount == 3)
    }

    @Test func absurdSensorValuesAreIgnored() {
        let smc = FakeSMC(values: ["Tp0T": 41.5, "Tp1T": 3000, "Te05": -40, "Tp2T": .nan])
        #expect(SMCProbe(smc: smc).temperature()?.celsius == 41.5)
    }

    @Test func fansCarryTheirMaximumWhenItIsReadable() {
        let smc = FakeSMC(values: ["FNum": 2, "F0Ac": 996, "F1Ac": 994, "F0Mx": 3625])
        let fans = SMCProbe(smc: smc).fans()
        #expect(fans?.fans.count == 2)
        #expect(fans?.fans.first?.rpm == 996)
        #expect(fans?.fans.first?.maxRPM == 3625)
        #expect(fans?.fans.last?.maxRPM == nil)
    }

    @Test func absurdFanMaximumsAreIgnored() {
        // A misbehaving SMC can return 3.4e38 for a float key; Int(that) would trap in the UI.
        let smc = FakeSMC(values: ["FNum": 1, "F0Ac": 1200, "F0Mx": 3.4e38])
        let fans = SMCProbe(smc: smc).fans()
        #expect(fans?.fans.first?.rpm == 1200)
        #expect(fans?.fans.first?.maxRPM == nil)
    }
}
