# EyesUpGuardian Plan 3: System Stats, Dashboard, Processes and HUD

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show what the Mac is doing — CPU, memory, power draw, temperature, fans, GPU, disk, network, uptime, processes, and which *other* apps are keeping it awake — in the dashboard's Overview and Processes tabs, four tiles in the popover, an optional menu-bar readout, and a pinnable floating HUD.

**Architecture:**
- One `MetricsCenter` owns sampling. UI surfaces subscribe to the metrics they show; the center samples the union of those at the fastest requested interval and stops entirely when nothing is subscribed. Probing runs off the main thread behind an injected executor, so tests run inline and deterministically.
- Every reading is a `MetricID` with an optional value in a `MetricsSnapshot`. A probe that can't read its source returns nil, and the UI shows "Not available on this Mac" rather than a fake number.
- Ring buffers of fixed length hold the last 5 minutes for the charts, so memory never grows.

**Tech Stack:** Swift 6.2, SwiftUI + AppKit (macOS 26), Mach (`host_processor_info`, `host_statistics64`), `sysctl`, libproc, IOKit (AppleSMC user client, IOAccelerator, `IOPMCopyAssertionsByProcess`), Swift Testing. No third-party dependencies, no `dlopen`.

**Spec:** `docs/superpowers/specs/2026-09-19-eyesupguardian-design.md` (§6 in full, §7.1 readout, §7.2 tiles, §7.3 Overview and Processes tabs, §7.4 HUD)

**Builds on:** branch `plan-1-core-menu-bar` with Plans 1 and 2 complete (holds, triggers, dashboard shell with Triggers and Settings tabs, `LiveSystemCounters`, `LiveProcessLister`, `SystemAssertions`).

## The feasibility spike is already done

Spec §6.2 makes a throwaway spike the first task of this plan. **It was run on the target Mac (Mac Studio M3 Ultra, macOS 26.7) before this plan was written**, so the tasks below state what works instead of guessing. Results, all **without admin rights**:

| Reading | Verdict | Evidence |
|---|---|---|
| **Total system power** | **Ships.** SMC key `PSTR` (also `PDTR`, `PD0R`) | 17.4 W idle, 23.8 W busy |
| **Fan speed** | **Ships.** `F0Ac`/`F1Ac` actual, `F0Mx` max, `FNum` count | 996 and 994 RPM, max 3625, 2 fans |
| **Temperature** | **Ships.** A curated key list, reporting the hottest | 38–60 °C across sensors |
| **GPU utilization** | **Ships.** `IOAccelerator` → `PerformanceStatistics` → `Device Utilization %` | 24% |
| **CPU / GPU / Neural Engine power split** | **Does not ship.** It needs IOReport via `dlopen`, which this app's own security guard forbids (Plan 2) and which we won't add to a security-focused app. Total watts covers the user-visible need. | — |
| Everything else in §6.2's documented list | Ships. CPU, memory, swap, uptime, load, idle, disk, network, processes, other apps' assertions all use documented APIs, several already built in Plan 2. | — |

**Measured costs that shape the design:**
- One SMC key read: **0.40 ms**. Six keys: **2.4 ms**.
- Enumerating all 3,364 SMC keys: **638 ms** — far too slow. The app therefore probes a **fixed curated key list once** and keeps the keys that answer.
- Reading all 209 temperature sensors: **61 ms** — also too slow per sample, hence the curated list.
- GPU statistics read: **0.07 ms**.

## Global Constraints

Everything from Plans 1 and 2 still holds:

- `// swift-tools-version: 6.2`, `platforms: [.macOS(.v26)]`, Swift 6 strict concurrency, **zero third-party dependencies**.
- App code never runs commands, never touches the network, never escalates privileges. `SecurityGuardTests` fails the build otherwise — **and it now forbids `dlopen`**, so no probe may use it.
- `EyesUpCore` must not import SwiftUI or AppKit.
- **Never use SwiftUI `@State`** (the macOS 27 SDK makes it a macro whose plugin ships only with Xcode). Use an `@Observable` class owned by the caller with `@Bindable`.
- Run tests with `make test` / `make test-integration`, never bare `swift test`.
- Idle budget (spec §3): **< 0.1% CPU over 60 s and ≤ 30 MB footprint**, enforced by `make perf`. Dashboard-open target: **< 1.5% CPU**, checked by hand.
- **Nothing is sampled unless a visible surface or an enabled trigger asks for it** (spec §3.1, §6.1). Cadences: menu-bar readout 2 s, popover and HUD 1 s, dashboard 1 s for the visible tab, processes 2 s.
- Chart history is a fixed-size ring buffer of **300 samples per metric** (spec §3.4).
- A probe that fails reports nil and the UI hides that stat (spec §3.8).
- End every commit message with `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.

## Decisions this plan records

1. **No IOReport, so no per-chip power split.** See the spike table. Task 13 updates spec §6.2.
2. **SMC keys are curated, not enumerated**, because enumeration costs 638 ms. The curated list is probed once at first use and cached; unreadable keys are dropped.
3. **"Temperature" is the hottest of the curated sensors**, labeled "SoC (hottest sensor)". Apple publishes no sensor map, so naming individual sensors would be guesswork.
4. **Processes are sampled at 2 s and limited to the top 100 by CPU.** A full sweep of ~340 processes costs ~2 ms; the cap bounds the table and the memory it holds.
5. **The Overview uses sparklines and tiles, not the mockup's arc gauges.** A line of history answers
   "is this rising?", which a gauge cannot, and one chart style keeps the tab readable at any window size.
6. **⌘1–⌘5 tab shortcuts (spec §7.3) wait for Plan 4**, which adds the global hotkey and the rest of
   Settings, so all keyboard handling lands together.
7. **Quit/Force Quit applies only to processes the user owns**, with a confirmation naming the process, and the process identity (PID + start time) is re-verified immediately before the signal (spec §7.3, §9.6).

## Review Focus

1. **Sampling that outlives its window.** Closing the dashboard, popover or HUD must stop that surface's sampling; with nothing visible and no stat readout chosen, the sampler must not run at all. Tests: Task 6 `stopsSamplingWhenTheLastSubscriberGoesAway`, `samplesOnlyTheUnionOfSubscribedMetrics`, `noTimerWhenNothingIsSubscribed`.
2. **A probe that starts failing mid-session** (SMC stops answering, a display sleeps, a disk unmounts) must blank that stat and leave the rest working, never crash or freeze the sampler. Tests: Task 6 `aFailingProbeLeavesOtherMetricsIntact`, Task 4 `unavailableKeysAreDroppedOnce`.
3. **Counters that jump after sleep** (network/disk bytes, CPU ticks) must not show an absurd spike on the first sample after wake. Tests: Task 3 `ratesResetAfterWake`, Task 6 `refreshDropsStaleBaselines`.
4. **Quitting a process that is gone, recycled or owned by someone else.** The app must refuse and say why, never signal an unrelated process. Tests: Task 5 `refusesToQuitAnotherUsersProcess`, `refusesWhenThePIDWasRecycled`, `refusesWhenTheProcessIsGone`.
5. **Absurd or missing readings** (zero total memory, NaN watts, a negative rate, an empty process list) must render as "—" rather than crash or print nonsense. Tests: Task 7 `formattersHandleMissingAndAbsurdValues`, Task 2 `memoryTotalsAreConsistent`.

---

## File map

```
Sources/EyesUpCore/Metrics/
├── MetricsModel.swift          Task 1: MetricID, MetricsSnapshot and the per-metric value types
├── MetricsCenter.swift         Task 6: subscriptions, cadence, ring buffers, executor
├── MetricsExecutor.swift       Task 6: MetricsProbing, MetricsExecuting, Inline/Background executors
├── Probes/CPUProbe.swift       Task 2: total, per core, P/E clusters
├── Probes/MemoryProbe.swift    Task 2: used/app/wired/compressed/pressure/swap
├── Probes/SystemProbe.swift    Task 2: uptime, load average, idle time, thermal state
├── Probes/StorageProbe.swift   Task 3: disk free + read/write rates
├── Probes/NetworkProbe.swift   Task 3: in/out rates
├── Probes/ProcessProbe.swift   Task 5: top processes by CPU
├── Probes/AssertionProbe.swift Task 5: other apps keeping the Mac awake
├── Probes/GPUProbe.swift       Task 4: IOAccelerator utilization
├── Probes/SMCProbe.swift       Task 4: power, fans, temperature (curated keys)
├── Probes/SMC.swift            Task 4: the AppleSMC user client itself
└── Probes/LiveProbes.swift     Task 6: composes every probe into one MetricsProbing

Sources/EyesUpCore/Processes/ProcessControl.swift   Task 5: quit / force quit, own processes only
Sources/EyesUpCore/Formatting/StatFormatting.swift  Task 7: bytes, percent, watts, °C, RPM, uptime

Sources/EyesUpApp/
├── Stats/StatTile.swift            Task 8: the shared tile view
├── Stats/Sparkline.swift           Task 9: the tiny history chart
├── Popover/PopoverView.swift       MODIFY Task 8: four tiles + other-apps warning row
├── MenuBar/StatusItemController.swift MODIFY Task 10: optional stat readout
├── Dashboard/OverviewTab.swift     Task 9: Ambient overview
├── Dashboard/ProcessesTab.swift    Task 11: Mission Control table
├── Dashboard/DashboardWindow.swift MODIFY Tasks 9, 11: two more tabs
├── Dashboard/SettingsTab.swift     MODIFY Task 10, 12: readout picker, HUD toggle
├── HUD/HUDWindow.swift             Task 12: floating panel
└── AppEnvironment.swift            MODIFY Task 6: owns the MetricsCenter

Tests/EyesUpCoreTests/
├── MetricsModelTests.swift     Task 1
├── ProbeTests.swift            Tasks 2, 3 (live, tolerant)
├── SMCProbeTests.swift         Task 4 (integration-gated)
├── ProcessControlTests.swift   Task 5
├── MetricsCenterTests.swift    Task 6
└── StatFormattingTests.swift   Task 7
Tests/EyesUpAppTests/StatViewModelTests.swift  Tasks 8, 10
docs/manual-test-checklist.md, README.md       MODIFY Task 13
```

---

### Task 1: Metric model

**Files:**
- Create: `Sources/EyesUpCore/Metrics/MetricsModel.swift`, `Tests/EyesUpCoreTests/MetricsModelTests.swift`

**Interfaces:**
- Produces:
  - `enum MetricID: String, CaseIterable, Sendable` — `cpu, memory, system, storage, network, processes, power, fans, temperature, gpu, otherAssertions`
  - `struct CPUMetrics { total: Double; cores: [Double]; performance: Double?; efficiency: Double? }`
  - `struct MemoryMetrics { usedBytes, appBytes, wiredBytes, compressedBytes, totalBytes, swapUsedBytes: UInt64; pressure: MemoryPressure }`, `enum MemoryPressure { normal, warning, critical }`
  - `struct SystemMetrics { bootTime: Date; loadAverage: (Double, Double, Double); idleSeconds: TimeInterval; thermal: ThermalLevel }`
  - `struct StorageMetrics { freeBytes, totalBytes: UInt64; readBytesPerSecond, writeBytesPerSecond: Double? }`
  - `struct NetworkMetrics { inBytesPerSecond, outBytesPerSecond: Double? }`
  - `struct ProcessEntry: Identifiable { pid: Int32; name: String; cpuPercent: Double; memoryBytes: UInt64; threads: Int; isOwn: Bool }`
  - `struct PowerMetrics { watts: Double }`, `struct FanMetrics { fans: [FanReading] }`, `struct FanReading { index: Int; rpm: Double; maxRPM: Double? }`
  - `struct TemperatureMetrics { celsius: Double; sensorCount: Int }`, `struct GPUMetrics { utilization: Double }`
  - `struct OtherAssertion: Hashable { processName: String; type: String }`
  - `struct MetricsSnapshot` with one optional property per metric, `var availableIDs: Set<MetricID>`, and `func merging(_ other: MetricsSnapshot) -> MetricsSnapshot`

- [ ] **Step 1: Write the failing tests**

`Tests/EyesUpCoreTests/MetricsModelTests.swift`:
```swift
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
        snapshot.processes = [ProcessEntry(pid: 1, name: "a", cpuPercent: 0, memoryBytes: 0, threads: 1, isOwn: false)]
        snapshot.power = PowerMetrics(watts: 1)
        snapshot.fans = FanMetrics(fans: [FanReading(index: 0, rpm: 1000, maxRPM: 3000)])
        snapshot.temperature = TemperatureMetrics(celsius: 40, sensorCount: 3)
        snapshot.gpu = GPUMetrics(utilization: 5)
        snapshot.otherAssertions = [OtherAssertion(processName: "Zoom", type: "PreventUserIdleDisplaySleep")]
        #expect(snapshot.availableIDs == Set(MetricID.allCases))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test`
Expected: FAIL to compile with `cannot find 'MetricsSnapshot' in scope`.

- [ ] **Step 3: Write the model**

`Sources/EyesUpCore/Metrics/MetricsModel.swift`:
```swift
import Foundation

/// One reading the app can sample. UI surfaces subscribe by these.
public enum MetricID: String, CaseIterable, Sendable {
    case cpu, memory, system, storage, network, processes, power, fans, temperature, gpu, otherAssertions
}

public struct CPUMetrics: Equatable, Sendable {
    public var total: Double
    public var cores: [Double]
    /// Averages per cluster; nil when the split can't be read.
    public var performance: Double?
    public var efficiency: Double?

    public init(total: Double, cores: [Double], performance: Double?, efficiency: Double?) {
        self.total = total
        self.cores = cores
        self.performance = performance
        self.efficiency = efficiency
    }
}

public enum MemoryPressure: String, Equatable, Sendable {
    case normal, warning, critical
}

public struct MemoryMetrics: Equatable, Sendable {
    public var usedBytes: UInt64
    public var appBytes: UInt64
    public var wiredBytes: UInt64
    public var compressedBytes: UInt64
    public var totalBytes: UInt64
    public var swapUsedBytes: UInt64
    public var pressure: MemoryPressure

    public init(usedBytes: UInt64, appBytes: UInt64, wiredBytes: UInt64, compressedBytes: UInt64,
                totalBytes: UInt64, swapUsedBytes: UInt64, pressure: MemoryPressure) {
        self.usedBytes = usedBytes
        self.appBytes = appBytes
        self.wiredBytes = wiredBytes
        self.compressedBytes = compressedBytes
        self.totalBytes = totalBytes
        self.swapUsedBytes = swapUsedBytes
        self.pressure = pressure
    }
}

public struct SystemMetrics: Equatable, Sendable {
    public var bootTime: Date
    public var loadAverage: (Double, Double, Double)
    public var idleSeconds: TimeInterval
    public var thermal: ThermalLevel

    public init(bootTime: Date, loadAverage: (Double, Double, Double), idleSeconds: TimeInterval, thermal: ThermalLevel) {
        self.bootTime = bootTime
        self.loadAverage = loadAverage
        self.idleSeconds = idleSeconds
        self.thermal = thermal
    }

    public static func == (lhs: SystemMetrics, rhs: SystemMetrics) -> Bool {
        lhs.bootTime == rhs.bootTime && lhs.loadAverage == rhs.loadAverage
            && lhs.idleSeconds == rhs.idleSeconds && lhs.thermal == rhs.thermal
    }
}

public struct StorageMetrics: Equatable, Sendable {
    public var freeBytes: UInt64
    public var totalBytes: UInt64
    /// nil until a second sample gives a rate.
    public var readBytesPerSecond: Double?
    public var writeBytesPerSecond: Double?

    public init(freeBytes: UInt64, totalBytes: UInt64, readBytesPerSecond: Double?, writeBytesPerSecond: Double?) {
        self.freeBytes = freeBytes
        self.totalBytes = totalBytes
        self.readBytesPerSecond = readBytesPerSecond
        self.writeBytesPerSecond = writeBytesPerSecond
    }
}

public struct NetworkMetrics: Equatable, Sendable {
    public var inBytesPerSecond: Double?
    public var outBytesPerSecond: Double?

    public init(inBytesPerSecond: Double?, outBytesPerSecond: Double?) {
        self.inBytesPerSecond = inBytesPerSecond
        self.outBytesPerSecond = outBytesPerSecond
    }
}

public struct ProcessEntry: Identifiable, Equatable, Sendable {
    public var id: Int32 { pid }
    public var pid: Int32
    public var name: String
    public var cpuPercent: Double
    public var memoryBytes: UInt64
    public var threads: Int
    public var isOwn: Bool

    public init(pid: Int32, name: String, cpuPercent: Double, memoryBytes: UInt64, threads: Int, isOwn: Bool) {
        self.pid = pid
        self.name = name
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.threads = threads
        self.isOwn = isOwn
    }
}

public struct PowerMetrics: Equatable, Sendable {
    public var watts: Double
    public init(watts: Double) { self.watts = watts }
}

public struct FanReading: Equatable, Sendable {
    public var index: Int
    public var rpm: Double
    public var maxRPM: Double?

    public init(index: Int, rpm: Double, maxRPM: Double?) {
        self.index = index
        self.rpm = rpm
        self.maxRPM = maxRPM
    }
}

public struct FanMetrics: Equatable, Sendable {
    public var fans: [FanReading]
    public init(fans: [FanReading]) { self.fans = fans }
}

public struct TemperatureMetrics: Equatable, Sendable {
    /// The hottest curated sensor: Apple publishes no sensor map, so naming one would be guesswork.
    public var celsius: Double
    public var sensorCount: Int

    public init(celsius: Double, sensorCount: Int) {
        self.celsius = celsius
        self.sensorCount = sensorCount
    }
}

public struct GPUMetrics: Equatable, Sendable {
    public var utilization: Double
    public init(utilization: Double) { self.utilization = utilization }
}

/// Another app holding a sleep assertion (spec §6.2).
public struct OtherAssertion: Hashable, Sendable {
    public var processName: String
    public var type: String

    public init(processName: String, type: String) {
        self.processName = processName
        self.type = type
    }
}

/// Everything the app knows right now. A nil slot means "not sampled" or "not available on this Mac".
public struct MetricsSnapshot: Equatable, Sendable {
    public var cpu: CPUMetrics?
    public var memory: MemoryMetrics?
    public var system: SystemMetrics?
    public var storage: StorageMetrics?
    public var network: NetworkMetrics?
    public var processes: [ProcessEntry]?
    public var power: PowerMetrics?
    public var fans: FanMetrics?
    public var temperature: TemperatureMetrics?
    public var gpu: GPUMetrics?
    public var otherAssertions: [OtherAssertion]?

    public init() {}

    public var availableIDs: Set<MetricID> {
        var ids: Set<MetricID> = []
        if cpu != nil { ids.insert(.cpu) }
        if memory != nil { ids.insert(.memory) }
        if system != nil { ids.insert(.system) }
        if storage != nil { ids.insert(.storage) }
        if network != nil { ids.insert(.network) }
        if processes != nil { ids.insert(.processes) }
        if power != nil { ids.insert(.power) }
        if fans != nil { ids.insert(.fans) }
        if temperature != nil { ids.insert(.temperature) }
        if gpu != nil { ids.insert(.gpu) }
        if otherAssertions != nil { ids.insert(.otherAssertions) }
        return ids
    }

    /// `other` wins wherever it has a reading; everything else is kept, so an unsubscribed
    /// metric doesn't blank out while a different surface is open.
    public func merging(_ other: MetricsSnapshot) -> MetricsSnapshot {
        var merged = self
        if let value = other.cpu { merged.cpu = value }
        if let value = other.memory { merged.memory = value }
        if let value = other.system { merged.system = value }
        if let value = other.storage { merged.storage = value }
        if let value = other.network { merged.network = value }
        if let value = other.processes { merged.processes = value }
        if let value = other.power { merged.power = value }
        if let value = other.fans { merged.fans = value }
        if let value = other.temperature { merged.temperature = value }
        if let value = other.gpu { merged.gpu = value }
        if let value = other.otherAssertions { merged.otherAssertions = value }
        return merged
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `make test`
Expected: all 4 `MetricsModelTests` pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/EyesUpCore/Metrics Tests/EyesUpCoreTests/MetricsModelTests.swift
git commit -m "feat(core): add the metric model and snapshot merging" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: CPU, memory and system probes

**Files:**
- Create: `Sources/EyesUpCore/Metrics/Probes/CPUProbe.swift`, `Sources/EyesUpCore/Metrics/Probes/MemoryProbe.swift`, `Sources/EyesUpCore/Metrics/Probes/SystemProbe.swift`, `Tests/EyesUpCoreTests/ProbeTests.swift`

**Interfaces:**
- Consumes: `CPUMeter` (Plan 2), the metric types from Task 1, `ThermalLevel` (Plan 2).
- Produces:
  - `final class CPUProbe { init(); func sample() -> CPUMetrics? }` (holds per-core tick baselines)
  - `struct MemoryProbe { init(); func sample() -> MemoryMetrics? }`
  - `struct SystemProbe { init(); func sample() -> SystemMetrics? }`

The Mac this ships on reports `hw.perflevel0.name = Performance` (24 cores) and `hw.perflevel1.name = Efficiency` (8). Apple Silicon numbers efficiency cores first, so the first `hw.perflevel1.logicalcpu` entries are the efficiency cluster.

- [ ] **Step 1: Write the failing tests**

`Tests/EyesUpCoreTests/ProbeTests.swift`:
```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test`
Expected: FAIL to compile with `cannot find 'CPUProbe' in scope`.

- [ ] **Step 3: Write the CPU probe**

`Sources/EyesUpCore/Metrics/Probes/CPUProbe.swift`:
```swift
import Darwin
import Foundation

/// Per-core busy percentages from Mach tick counters. The first sample only sets a baseline.
public final class CPUProbe {
    private var previous: [(busy: UInt64, total: UInt64)] = []
    private let efficiencyCoreCount: Int

    public init() {
        efficiencyCoreCount = Self.sysctlInt("hw.perflevel1.logicalcpu") ?? 0
    }

    public func sample() -> CPUMetrics? {
        guard let current = Self.coreTicks() else { return nil }
        defer { previous = current }
        guard previous.count == current.count, !current.isEmpty else { return nil }

        var cores: [Double] = []
        var busyDelta: UInt64 = 0
        var totalDelta: UInt64 = 0
        for (index, ticks) in current.enumerated() {
            let last = previous[index]
            guard ticks.total > last.total, ticks.busy >= last.busy else { return nil } // counters reset
            let busy = ticks.busy - last.busy
            let total = ticks.total - last.total
            busyDelta += busy
            totalDelta += total
            cores.append(Double(busy) / Double(total) * 100)
        }
        guard totalDelta > 0 else { return nil }

        // Apple Silicon numbers efficiency cores first.
        let efficiency = efficiencyCoreCount > 0 && efficiencyCoreCount <= cores.count
            ? cores.prefix(efficiencyCoreCount).reduce(0, +) / Double(efficiencyCoreCount)
            : nil
        let performanceCores = efficiencyCoreCount < cores.count ? Array(cores.dropFirst(efficiencyCoreCount)) : []
        let performance = performanceCores.isEmpty ? nil : performanceCores.reduce(0, +) / Double(performanceCores.count)

        return CPUMetrics(
            total: Double(busyDelta) / Double(totalDelta) * 100,
            cores: cores,
            performance: performance,
            efficiency: efficiency
        )
    }

    private static func coreTicks() -> [(busy: UInt64, total: UInt64)]? {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        var ticks: [(busy: UInt64, total: UInt64)] = []
        ticks.reserveCapacity(Int(count))
        for core in 0..<Int(count) {
            let base = core * Int(CPU_STATE_MAX)
            let user = UInt64(info[base + Int(CPU_STATE_USER)])
            let system = UInt64(info[base + Int(CPU_STATE_SYSTEM)])
            let idle = UInt64(info[base + Int(CPU_STATE_IDLE)])
            let nice = UInt64(info[base + Int(CPU_STATE_NICE)])
            ticks.append((busy: user + system + nice, total: user + system + nice + idle))
        }
        return ticks
    }

    private static func sysctlInt(_ name: String) -> Int? {
        var value: Int = 0
        var size = MemoryLayout<Int>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }
}
```

- [ ] **Step 4: Write the memory probe**

`Sources/EyesUpCore/Metrics/Probes/MemoryProbe.swift`:
```swift
import Darwin
import Foundation

/// Memory as Activity Monitor reports it: used, app, wired, compressed, plus pressure and swap.
public struct MemoryProbe {
    public init() {}

    public func sample() -> MemoryMetrics? {
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let pageSize = UInt64(vm_kernel_page_size)
        let wired = UInt64(statistics.wire_count) * pageSize
        let compressed = UInt64(statistics.compressor_page_count) * pageSize
        let active = UInt64(statistics.active_count) * pageSize
        let speculative = UInt64(statistics.speculative_count) * pageSize
        let purgeable = UInt64(statistics.purgeable_count) * pageSize
        let external = UInt64(statistics.external_page_count) * pageSize
        // Activity Monitor's "App Memory": anonymous pages that aren't file-backed or purgeable.
        let app = active + speculative > purgeable + external ? active + speculative - purgeable - external : 0
        let used = app + wired + compressed

        return MemoryMetrics(
            usedBytes: min(used, ProcessInfo.processInfo.physicalMemory),
            appBytes: app,
            wiredBytes: wired,
            compressedBytes: compressed,
            totalBytes: ProcessInfo.processInfo.physicalMemory,
            swapUsedBytes: Self.swapUsed(),
            pressure: Self.pressure()
        )
    }

    private static func swapUsed() -> UInt64 {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return 0 }
        return usage.xsu_used
    }

    private static func pressure() -> MemoryPressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return .normal }
        switch level {
        case 4: return .critical
        case 2: return .warning
        default: return .normal
        }
    }
}
```

- [ ] **Step 5: Write the system probe**

`Sources/EyesUpCore/Metrics/Probes/SystemProbe.swift`:
```swift
import Darwin
import Foundation
import IOKit

/// Uptime, load average, how long since you touched the Mac, and thermal state.
public struct SystemProbe {
    public init() {}

    public func sample() -> SystemMetrics? {
        guard let bootTime = Self.bootTime() else { return nil }
        var loads = [Double](repeating: 0, count: 3)
        let count = getloadavg(&loads, 3)
        let thermal: ThermalLevel = switch ProcessInfo.processInfo.thermalState {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .nominal
        }
        return SystemMetrics(
            bootTime: bootTime,
            loadAverage: count == 3 ? (loads[0], loads[1], loads[2]) : (0, 0, 0),
            idleSeconds: Self.idleSeconds() ?? 0,
            thermal: thermal
        )
    }

    private static func bootTime() -> Date? {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &boot, &size, nil, 0) == 0, boot.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(boot.tv_sec))
    }

    /// Seconds since the last keyboard or mouse event, from the HID system's idle counter.
    private static func idleSeconds() -> TimeInterval? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let properties = IORegistryEntryCreateCFProperty(service, "HIDIdleTime" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? NSNumber else { return nil }
        return TimeInterval(properties.uint64Value) / 1_000_000_000
    }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `make test`
Expected: all 3 `ProbeTests` pass. If `cpuProbeNeedsTwoSamplesThenReportsSanePercentages` reports a core count mismatch, the machine hot-plugged a core between samples; re-run once before investigating.

- [ ] **Step 7: Commit**

```bash
git add Sources/EyesUpCore/Metrics/Probes Tests/EyesUpCoreTests/ProbeTests.swift
git commit -m "feat(core): add CPU, memory and system probes" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: Storage and network probes

**Files:**
- Create: `Sources/EyesUpCore/Metrics/Probes/StorageProbe.swift`, `Sources/EyesUpCore/Metrics/Probes/NetworkProbe.swift`
- Modify: `Tests/EyesUpCoreTests/ProbeTests.swift`

**Interfaces:**
- Consumes: `SystemCounters` and `LiveSystemCounters` (Plan 2), `RateMeter` (Plan 2).
- Produces:
  - `final class StorageProbe { init(counters:clock:); func sample() -> StorageMetrics?; func resetBaseline() }`
  - `final class NetworkProbe { init(counters:clock:); func sample() -> NetworkMetrics?; func resetBaseline() }`

Both reuse Plan 2's counters, which already read `IOBlockStorageDriver` statistics and the 64-bit interface list.

- [ ] **Step 1: Write the failing tests**

Append inside `@Suite struct ProbeTests` in `Tests/EyesUpCoreTests/ProbeTests.swift`:
```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test`
Expected: FAIL to compile with `cannot find 'StorageProbe' in scope`.

- [ ] **Step 3: Write the probes**

`Sources/EyesUpCore/Metrics/Probes/StorageProbe.swift`:
```swift
import Foundation

/// Free space on the boot volume, plus read/write rates from the block storage counters.
public final class StorageProbe {
    private let counters: any SystemCounters
    private let clock: any WallClock
    private var readMeter = RateMeter()
    private var writeMeter = RateMeter()

    public init(counters: any SystemCounters = LiveSystemCounters(), clock: any WallClock = SystemClock()) {
        self.counters = counters
        self.clock = clock
    }

    /// After a wake, the counters have jumped; start again rather than report a fake burst.
    public func resetBaseline() {
        readMeter = RateMeter()
        writeMeter = RateMeter()
    }

    public func sample() -> StorageMetrics? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]),
              let total = values.volumeTotalCapacity, total > 0 else { return nil }
        let free = UInt64(max(0, values.volumeAvailableCapacityForImportantUsage ?? 0))
        let now = clock.now
        let write = counters.diskBytesWritten().flatMap { writeMeter.rate(for: $0, at: now) }
        let read = counters.diskBytesRead().flatMap { readMeter.rate(for: $0, at: now) }
        return StorageMetrics(
            freeBytes: min(free, UInt64(total)),
            totalBytes: UInt64(total),
            readBytesPerSecond: read,
            writeBytesPerSecond: write
        )
    }
}
```

`Sources/EyesUpCore/Metrics/Probes/NetworkProbe.swift`:
```swift
import Foundation

/// Network throughput in and out, from the 64-bit interface counters.
public final class NetworkProbe {
    private let counters: any SystemCounters
    private let clock: any WallClock
    private var inMeter = RateMeter()
    private var outMeter = RateMeter()

    public init(counters: any SystemCounters = LiveSystemCounters(), clock: any WallClock = SystemClock()) {
        self.counters = counters
        self.clock = clock
    }

    public func resetBaseline() {
        inMeter = RateMeter()
        outMeter = RateMeter()
    }

    public func sample() -> NetworkMetrics? {
        let now = clock.now
        guard let split = counters.networkBytesSplit() else {
            // Only the combined counter is available; report it as inbound so the number isn't lost.
            guard let total = counters.networkBytes() else { return nil }
            return NetworkMetrics(inBytesPerSecond: inMeter.rate(for: total, at: now), outBytesPerSecond: nil)
        }
        return NetworkMetrics(
            inBytesPerSecond: inMeter.rate(for: split.received, at: now),
            outBytesPerSecond: outMeter.rate(for: split.sent, at: now)
        )
    }
}
```

- [ ] **Step 4: Extend the counters with the two readings the probes need**

Plan 2's `SystemCounters` gives combined network bytes and written disk bytes. Add read bytes and the in/out split.

In `Sources/EyesUpCore/Triggers/SystemSources.swift`, replace the `SystemCounters` protocol with:
```swift
/// Raw counters behind the activity triggers and the stats probes.
public protocol SystemCounters: Sendable {
    func cpuTicks() -> (busy: UInt64, total: UInt64)?
    func networkBytes() -> UInt64?
    func diskBytesWritten() -> UInt64?
    /// Bytes received and sent separately; nil when the interface list can't be read.
    func networkBytesSplit() -> (received: UInt64, sent: UInt64)?
    func diskBytesRead() -> UInt64?
}

extension SystemCounters {
    public func networkBytesSplit() -> (received: UInt64, sent: UInt64)? { nil }
    public func diskBytesRead() -> UInt64? { nil }
}
```

In `Sources/EyesUpCore/System/LiveSystemSources.swift`, replace `networkBytes()` and `diskBytesWritten()` with implementations that share one pass:
```swift
    public func networkBytes() -> UInt64? {
        guard let split = networkBytesSplit() else { return nil }
        return split.received + split.sent
    }

    /// Bytes in and out across every non-loopback interface, from the 64-bit interface list.
    public func networkBytesSplit() -> (received: UInt64, sent: UInt64)? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else { return nil }

        var received: UInt64 = 0
        var sent: UInt64 = 0
        var offset = 0
        buffer.withUnsafeBytes { raw in
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                guard header.ifm_msglen > 0 else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2, offset + MemoryLayout<if_msghdr2>.size <= length {
                    let extended = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    if extended.ifm_data.ifi_type != UInt8(IFT_LOOP) {
                        received += extended.ifm_data.ifi_ibytes
                        sent += extended.ifm_data.ifi_obytes
                    }
                }
                offset += Int(header.ifm_msglen)
            }
        }
        return (received, sent)
    }

    public func diskBytesWritten() -> UInt64? { blockStorageBytes()?.written }

    public func diskBytesRead() -> UInt64? { blockStorageBytes()?.read }

    private func blockStorageBytes() -> (read: UInt64, written: UInt64)? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var read: UInt64 = 0
        var written: UInt64 = 0
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let statistics = IORegistryEntryCreateCFProperty(service, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] else { continue }
            if let value = statistics["Bytes (Read)"] as? NSNumber { read += value.uint64Value }
            if let value = statistics["Bytes (Write)"] as? NSNumber { written += value.uint64Value }
        }
        return (read, written)
    }
```

Add the two new readings to `FakeCounters` in `Tests/EyesUpCoreTests/Support/TriggerFakes.swift`:
```swift
    func networkBytesSplit() -> (received: UInt64, sent: UInt64)? {
        network.map { (received: $0 / 2, sent: $0 / 2) }
    }

    func diskBytesRead() -> UInt64? { disk }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `make test`
Expected: the 3 new `ProbeTests` pass and Plan 2's activity-trigger tests stay green.

- [ ] **Step 6: Commit**

```bash
git add Sources/EyesUpCore Tests/EyesUpCoreTests
git commit -m "feat(core): add storage and network probes with wake-safe rates" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: SMC and GPU probes (power, fans, temperature, GPU)

**Files:**
- Create: `Sources/EyesUpCore/Metrics/Probes/SMC.swift`, `Sources/EyesUpCore/Metrics/Probes/SMCProbe.swift`, `Sources/EyesUpCore/Metrics/Probes/GPUProbe.swift`, `Tests/EyesUpCoreTests/SMCProbeTests.swift`

**Interfaces:**
- Produces:
  - `final class SMC { init?(); func read(_ key: String) -> Double?; func close() }`
  - `final class SMCProbe { init(smc:); var isAvailable: Bool; func power() -> PowerMetrics?; func fans() -> FanMetrics?; func temperature() -> TemperatureMetrics? }`
  - `struct GPUProbe { init(); func sample() -> GPUMetrics? }`

**Everything here was proven on the target Mac by the spike** (see the table at the top): `PSTR` gives total watts, `F0Ac`/`F1Ac`/`F0Mx`/`FNum` give fans, the curated temperature keys give 38–60 °C, and `IOAccelerator` gives GPU utilization. Two details the spike settled and the code must respect:
1. **The key field is a native-endian `UInt32`**, while the payload stays big-endian. Getting this backwards returns "key not found" (`0x84`) for every key.
2. **The struct is 80 bytes with C layout.** Swift's own layout rules don't match, so the code builds the request as a byte buffer with explicit offsets.

- [ ] **Step 1: Write the failing tests**

`Tests/EyesUpCoreTests/SMCProbeTests.swift`:
```swift
import Foundation
import Testing
@testable import EyesUpCore

@Suite struct SMCProbeTests {
    @Test func gpuUtilizationIsAPercentage() throws {
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
}
```

Append to `Tests/EyesUpCoreTests/Support/TriggerFakes.swift`:
```swift
final class FakeSMC: SMCReading, @unchecked Sendable {
    private let values: [String: Double]
    private(set) var readCount = 0

    init(values: [String: Double]) { self.values = values }

    func read(_ key: String) -> Double? {
        readCount += 1
        return values[key]
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test`
Expected: FAIL to compile with `cannot find type 'SMCReading' in scope`.

- [ ] **Step 3: Write the SMC client**

`Sources/EyesUpCore/Metrics/Probes/SMC.swift`:
```swift
import Foundation
import IOKit

/// What SMCProbe needs from the SMC, so tests can supply readings without hardware.
public protocol SMCReading: AnyObject, Sendable {
    func read(_ key: String) -> Double?
}

/// Reads Apple's System Management Controller through its IOKit user client. No admin rights needed.
///
/// The request is an 80-byte C struct, built here as raw bytes because Swift's layout rules don't
/// match C's. The key field is a *native-endian* UInt32 while the payload stays big-endian; swapping
/// them makes every key come back "not found".
public final class SMC: SMCReading, @unchecked Sendable {
    private var connection: io_connect_t = 0
    private let lock = NSLock()

    private static let structSize = 80
    private static let keyOffset = 0
    private static let dataSizeOffset = 28
    private static let dataTypeOffset = 32
    private static let data8Offset = 42
    private static let bytesOffset = 48
    private static let selectorReadKey: UInt8 = 5
    private static let selectorKeyInfo: UInt8 = 9

    public init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else { return nil }
    }

    public func close() {
        lock.lock()
        defer { lock.unlock() }
        if connection != 0 {
            IOServiceClose(connection)
            connection = 0
        }
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    public func read(_ key: String) -> Double? {
        guard key.utf8.count == 4 else { return nil }
        lock.lock()
        defer { lock.unlock() }
        guard connection != 0 else { return nil }

        var info = [UInt8](repeating: 0, count: Self.structSize)
        Self.writeNative(&info, Self.keyOffset, Self.fourCharCode(key))
        info[Self.data8Offset] = Self.selectorKeyInfo
        guard let infoOut = call(info) else { return nil }
        let size = Int(Self.readNative(infoOut, Self.dataSizeOffset))
        let typeCode = Self.readNative(infoOut, Self.dataTypeOffset)
        guard size > 0, size <= 32 else { return nil }

        var request = [UInt8](repeating: 0, count: Self.structSize)
        Self.writeNative(&request, Self.keyOffset, Self.fourCharCode(key))
        Self.writeNative(&request, Self.dataSizeOffset, UInt32(size))
        Self.writeNative(&request, Self.dataTypeOffset, typeCode)
        request[Self.data8Offset] = Self.selectorReadKey
        guard let out = call(request) else { return nil }

        let payload = Array(out[Self.bytesOffset..<(Self.bytesOffset + size)])
        return Self.decode(payload, type: Self.string(typeCode))
    }

    private func call(_ input: [UInt8]) -> [UInt8]? {
        var output = [UInt8](repeating: 0, count: Self.structSize)
        var outputSize = Self.structSize
        let result = input.withUnsafeBytes { inputPointer in
            output.withUnsafeMutableBytes { outputPointer in
                IOConnectCallStructMethod(connection, 2, inputPointer.baseAddress, Self.structSize,
                                          outputPointer.baseAddress, &outputSize)
            }
        }
        return result == kIOReturnSuccess ? output : nil
    }

    private static func decode(_ payload: [UInt8], type: String) -> Double? {
        switch type.trimmingCharacters(in: CharacterSet(charactersIn: " \0")) {
        case "flt" where payload.count == 4:
            let bits = UInt32(payload[0]) | UInt32(payload[1]) << 8 | UInt32(payload[2]) << 16 | UInt32(payload[3]) << 24
            let value = Double(Float(bitPattern: bits))
            return value.isFinite ? value : nil
        case "ui8" where payload.count >= 1:
            return Double(payload[0])
        case "ui16" where payload.count >= 2:
            return Double(UInt16(payload[0]) << 8 | UInt16(payload[1]))
        case "ui32" where payload.count >= 4:
            return Double((UInt32(payload[0]) << 24) | (UInt32(payload[1]) << 16) | (UInt32(payload[2]) << 8) | UInt32(payload[3]))
        case "sp78" where payload.count >= 2:
            return Double(Int16(bitPattern: UInt16(payload[0]) << 8 | UInt16(payload[1]))) / 256
        case "fpe2" where payload.count >= 2:
            return Double(UInt16(payload[0]) << 8 | UInt16(payload[1])) / 4
        default:
            return nil
        }
    }

    private static func fourCharCode(_ key: String) -> UInt32 {
        var value: UInt32 = 0
        for byte in key.utf8.prefix(4) { value = (value << 8) | UInt32(byte) }
        return value
    }

    private static func string(_ code: UInt32) -> String {
        var result = ""
        for shift in stride(from: 24, through: 0, by: -8) {
            let byte = UInt8(truncatingIfNeeded: code >> UInt32(shift))
            if byte != 0 { result.append(Character(UnicodeScalar(byte))) }
        }
        return result
    }

    private static func writeNative(_ buffer: inout [UInt8], _ offset: Int, _ value: UInt32) {
        buffer[offset] = UInt8(truncatingIfNeeded: value)
        buffer[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
        buffer[offset + 2] = UInt8(truncatingIfNeeded: value >> 16)
        buffer[offset + 3] = UInt8(truncatingIfNeeded: value >> 24)
    }

    private static func readNative(_ buffer: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(buffer[offset]) | (UInt32(buffer[offset + 1]) << 8)
            | (UInt32(buffer[offset + 2]) << 16) | (UInt32(buffer[offset + 3]) << 24)
    }
}
```

- [ ] **Step 4: Write the SMC probe**

`Sources/EyesUpCore/Metrics/Probes/SMCProbe.swift`:
```swift
import Foundation

/// Power, fans and temperature from a curated key list.
///
/// Enumerating all 3,364 SMC keys costs 638 ms and reading all 209 temperature sensors costs 61 ms,
/// so the probe tries a fixed list once, keeps the keys that answer, and reads only those afterwards.
public final class SMCProbe {
    /// Whole-system power draw. `PSTR` answers on Apple Silicon desktops; the others are fallbacks.
    public static let powerKeys = ["PSTR", "PDTR", "PD0R"]
    /// Curated sensors: SoC clusters, then enclosure. The hottest readable one is reported.
    public static let temperatureKeys = ["Tp0T", "Tp1T", "Tp2T", "Tp3T", "Tp0o", "Tc02", "TVXs", "Te05", "TH0x"]
    public static let maxFans = 4

    private let smc: any SMCReading
    private var resolvedPowerKey: String?
    private var resolvedTemperatureKeys: [String]?
    private var resolvedFans: [(rpmKey: String, maxKey: String)]?
    private var probed = false

    public init(smc: any SMCReading) {
        self.smc = smc
    }

    /// True once any curated key has answered.
    public var isAvailable: Bool {
        resolveIfNeeded()
        return resolvedPowerKey != nil || !(resolvedTemperatureKeys ?? []).isEmpty || !(resolvedFans ?? []).isEmpty
    }

    public func power() -> PowerMetrics? {
        resolveIfNeeded()
        guard let key = resolvedPowerKey, let watts = smc.read(key), watts.isFinite, watts > 0, watts < 2000 else { return nil }
        return PowerMetrics(watts: watts)
    }

    public func temperature() -> TemperatureMetrics? {
        resolveIfNeeded()
        guard let keys = resolvedTemperatureKeys, !keys.isEmpty else { return nil }
        let readings = keys.compactMap { key -> Double? in
            guard let value = smc.read(key), Self.isPlausibleTemperature(value) else { return nil }
            return value
        }
        guard let hottest = readings.max() else { return nil }
        return TemperatureMetrics(celsius: hottest, sensorCount: readings.count)
    }

    public func fans() -> FanMetrics? {
        resolveIfNeeded()
        guard let resolved = resolvedFans, !resolved.isEmpty else { return nil }
        let readings = resolved.enumerated().compactMap { index, keys -> FanReading? in
            guard let rpm = smc.read(keys.rpmKey), rpm.isFinite, rpm >= 0, rpm < 20_000 else { return nil }
            let maximum = smc.read(keys.maxKey)
            return FanReading(index: index, rpm: rpm, maxRPM: maximum.flatMap { $0.isFinite && $0 > 0 ? $0 : nil })
        }
        return readings.isEmpty ? nil : FanMetrics(fans: readings)
    }

    private static func isPlausibleTemperature(_ value: Double) -> Bool {
        value.isFinite && value > 5 && value < 120
    }

    /// Tries the curated list once. Keys that don't answer are never asked again.
    private func resolveIfNeeded() {
        guard !probed else { return }
        probed = true
        resolvedPowerKey = Self.powerKeys.first { smc.read($0) != nil }
        resolvedTemperatureKeys = Self.temperatureKeys.filter { key in
            guard let value = smc.read(key) else { return false }
            return Self.isPlausibleTemperature(value)
        }
        let fanCount = smc.read("FNum").map { Int($0) } ?? 0
        resolvedFans = (0..<min(max(fanCount, 0), Self.maxFans)).compactMap { index in
            let rpmKey = "F\(index)Ac"
            guard smc.read(rpmKey) != nil else { return nil }
            return (rpmKey: rpmKey, maxKey: "F\(index)Mx")
        }
    }
}
```

- [ ] **Step 5: Write the GPU probe**

`Sources/EyesUpCore/Metrics/Probes/GPUProbe.swift`:
```swift
import Foundation
import IOKit

/// GPU utilization from the accelerator's published statistics — a registry read, not a private API.
public struct GPUProbe {
    public init() {}

    public func sample() -> GPUMetrics? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let statistics = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any],
                let utilization = statistics["Device Utilization %"] as? NSNumber else { continue }
            let value = utilization.doubleValue
            guard value.isFinite else { return nil }
            return GPUMetrics(utilization: min(max(value, 0), 100))
        }
        return nil
    }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `make test`
Expected: the 5 non-integration `SMCProbeTests` pass; the hardware one is skipped.
Run: `make test-integration`
Expected: all 6 pass, including real power, fan and temperature readings.

- [ ] **Step 7: Commit**

```bash
git add Sources/EyesUpCore/Metrics/Probes Tests/EyesUpCoreTests
git commit -m "feat(core): add SMC power/fan/temperature and GPU probes" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: Process probe, process control and other apps' assertions

**Files:**
- Create: `Sources/EyesUpCore/Metrics/Probes/ProcessProbe.swift`, `Sources/EyesUpCore/Metrics/Probes/AssertionProbe.swift`, `Sources/EyesUpCore/Processes/ProcessControl.swift`, `Tests/EyesUpCoreTests/ProcessControlTests.swift`
- Modify: `Sources/EyesUpCore/Processes/ProcessInspecting.swift` (add owner and resource details)

**Interfaces:**
- Consumes: `ProcessIdentity`, `ProcessInspecting`, `LibprocInspector` (Plan 1), `SystemAssertions` (Plan 1).
- Produces:
  - `ProcessInspecting.ownerUID(of: Int32) -> uid_t?` and `details(of: Int32) -> ProcessDetails?` where `ProcessDetails { name: String; cpuSeconds: Double; memoryBytes: UInt64; threads: Int; uid: uid_t; identity: ProcessIdentity }`
  - `final class ProcessProbe { init(inspector:clock:ownUID:); func sample() -> [ProcessEntry]?; static let limit = 100 }`
  - `struct AssertionProbe { init(ownPID:); func sample() -> [OtherAssertion]? }`
  - `enum ProcessControlError: Error { notYours, gone, recycled }` with `message`
  - `struct ProcessControl { init(inspector:ownUID:signaller:); func quit(_ identity: ProcessIdentity, force: Bool) throws }`
  - `protocol ProcessSignalling: Sendable { func send(_ signal: Int32, to pid: Int32) -> Bool }`, `struct POSIXSignaller`

- [ ] **Step 1: Write the failing tests**

`Tests/EyesUpCoreTests/ProcessControlTests.swift`:
```swift
import Foundation
import Testing
@testable import EyesUpCore

@Suite struct ProcessControlTests {
    private let mine = ProcessIdentity(pid: 4242, startTime: 100)

    private func inspector(uid: uid_t, identity: ProcessIdentity?) -> FakeInspector {
        let inspector = FakeInspector()
        if let identity {
            inspector.identities[identity.pid] = identity
            inspector.owners[identity.pid] = uid
            inspector.names[identity.pid] = "victim"
        }
        return inspector
    }

    @Test func quitsYourOwnProcess() throws {
        let signaller = FakeSignaller()
        let control = ProcessControl(inspector: inspector(uid: 501, identity: mine), ownUID: 501, signaller: signaller)
        try control.quit(mine, force: false)
        #expect(signaller.sent == [(SIGTERM, 4242)])

        try control.quit(mine, force: true)
        #expect(signaller.sent.last?.0 == SIGKILL)
    }

    @Test func refusesToQuitAnotherUsersProcess() {
        let signaller = FakeSignaller()
        let control = ProcessControl(inspector: inspector(uid: 0, identity: mine), ownUID: 501, signaller: signaller)
        #expect(throws: ProcessControlError.notYours) { try control.quit(mine, force: false) }
        #expect(signaller.sent.isEmpty)
    }

    @Test func refusesWhenTheProcessIsGone() {
        let signaller = FakeSignaller()
        let control = ProcessControl(inspector: inspector(uid: 501, identity: nil), ownUID: 501, signaller: signaller)
        #expect(throws: ProcessControlError.gone) { try control.quit(mine, force: false) }
        #expect(signaller.sent.isEmpty)
    }

    @Test func refusesWhenThePIDWasRecycled() {
        // Same PID, different start time: a different process now owns that number.
        let signaller = FakeSignaller()
        let recycled = ProcessIdentity(pid: 4242, startTime: 999)
        let control = ProcessControl(inspector: inspector(uid: 501, identity: recycled), ownUID: 501, signaller: signaller)
        #expect(throws: ProcessControlError.recycled) { try control.quit(mine, force: false) }
        #expect(signaller.sent.isEmpty)
    }

    @Test func processProbeRanksByCPUAndMarksYourOwn() throws {
        let inspector = FakeInspector()
        let clock = FakeClock()
        for (pid, cpu, uid) in [(Int32(1), 10.0, uid_t(0)), (2, 50.0, 501), (3, 5.0, 501)] {
            inspector.identities[pid] = ProcessIdentity(pid: pid, startTime: 1)
            inspector.details[pid] = ProcessDetails(name: "p\(pid)", cpuSeconds: 0, memoryBytes: UInt64(pid) * 1000,
                                                    threads: 2, uid: uid, identity: ProcessIdentity(pid: pid, startTime: 1))
            inspector.cpuSecondsByPID[pid] = cpu
        }
        inspector.allPIDs = [1, 2, 3]
        let probe = ProcessProbe(inspector: inspector, clock: clock, ownUID: 501)
        #expect(probe.sample()?.isEmpty == true) // first pass is a baseline

        clock.advance(1)
        for pid in [Int32(1), 2, 3] { inspector.cpuSecondsByPID[pid, default: 0] += Double(pid) * 0.1 }
        let entries = try #require(probe.sample())
        #expect(entries.map(\.pid) == [3, 2, 1]) // highest CPU first
        #expect(entries.first { $0.pid == 1 }?.isOwn == false)
        #expect(entries.first { $0.pid == 2 }?.isOwn == true)
    }

    @Test func assertionProbeExcludesOurOwnHolds() {
        let probe = AssertionProbe(ownPID: getpid())
        let others = probe.sample() ?? []
        #expect(!others.contains { $0.processName == "EyesUpGuardian" })
    }
}
```

Append to `Tests/EyesUpCoreTests/Support/TriggerFakes.swift`:
```swift
final class FakeSignaller: ProcessSignalling, @unchecked Sendable {
    private(set) var sent: [(Int32, Int32)] = []

    func send(_ signal: Int32, to pid: Int32) -> Bool {
        sent.append((signal, pid))
        return true
    }
}
```

And extend `FakeInspector` in the same file with the new lookups:
```swift
extension FakeInspector {
    func ownerUID(of pid: Int32) -> uid_t? { owners[pid] }

    func details(of pid: Int32) -> ProcessDetails? {
        guard var detail = details[pid] else { return nil }
        detail.cpuSeconds = cpuSecondsByPID[pid] ?? 0
        return detail
    }

    func allProcessIDs() -> [Int32] { allPIDs }
}
```
(Its stored properties `owners`, `details`, `cpuSecondsByPID` and `allPIDs` are added in Step 3.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test`
Expected: FAIL to compile with `cannot find 'ProcessControl' in scope`.

- [ ] **Step 3: Widen the inspector**

In `Sources/EyesUpCore/Processes/ProcessInspecting.swift`, replace the protocol and add the details type:
```swift
/// What one process looks like right now.
public struct ProcessDetails: Equatable, Sendable {
    public var name: String
    /// Total CPU seconds this process has used since it started.
    public var cpuSeconds: Double
    public var memoryBytes: UInt64
    public var threads: Int
    public var uid: uid_t
    public var identity: ProcessIdentity

    public init(name: String, cpuSeconds: Double, memoryBytes: UInt64, threads: Int, uid: uid_t, identity: ProcessIdentity) {
        self.name = name
        self.cpuSeconds = cpuSeconds
        self.memoryBytes = memoryBytes
        self.threads = threads
        self.uid = uid
        self.identity = identity
    }
}

public protocol ProcessInspecting: Sendable {
    func identity(of pid: Int32) -> ProcessIdentity?
    func name(of pid: Int32) -> String?
    func ownerUID(of pid: Int32) -> uid_t?
    func details(of pid: Int32) -> ProcessDetails?
    func allProcessIDs() -> [Int32]
}
```

Add these to `LibprocInspector` in the same file:
```swift
    public func ownerUID(of pid: Int32) -> uid_t? {
        bsdInfo(pid).map { $0.pbi_uid }
    }

    public func allProcessIDs() -> [Int32] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let written = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard written > 0 else { return [] }
        return pids.prefix(Int(written)).filter { $0 > 0 }
    }

    /// Resource usage for one process. Fails for processes this user can't inspect, which is expected.
    public func details(of pid: Int32) -> ProcessDetails? {
        guard let info = bsdInfo(pid), let identity = identity(of: pid) else { return nil }
        var usage = rusage_info_v4()
        let usageRead = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        var taskInfo = proc_taskinfo()
        let taskSize = Int32(MemoryLayout<proc_taskinfo>.size)
        let taskRead = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, taskSize) == taskSize

        let cpuSeconds = usageRead == 0
            ? Double(usage.ri_user_time + usage.ri_system_time) / 1_000_000_000
            : (taskRead ? Double(taskInfo.pti_total_user + taskInfo.pti_total_system) / 1_000_000_000 : 0)
        let memory = usageRead == 0 ? usage.ri_phys_footprint : (taskRead ? UInt64(taskInfo.pti_resident_size) : 0)

        return ProcessDetails(
            name: name(of: pid) ?? "process \(pid)",
            cpuSeconds: cpuSeconds,
            memoryBytes: memory,
            threads: taskRead ? Int(taskInfo.pti_threadnum) : 0,
            uid: info.pbi_uid,
            identity: identity
        )
    }
```

Add the matching stored properties to `FakeInspector` in `Tests/EyesUpCoreTests/Support/TriggerFakes.swift`:
```swift
    var owners: [Int32: uid_t] = [:]
    var details: [Int32: ProcessDetails] = [:]
    var cpuSecondsByPID: [Int32: Double] = [:]
    var allPIDs: [Int32] = []
```

- [ ] **Step 4: Write the process probe and assertion probe**

`Sources/EyesUpCore/Metrics/Probes/ProcessProbe.swift`:
```swift
import Foundation

/// The busiest processes, by CPU used between samples. Processes this user can't inspect are skipped.
public final class ProcessProbe {
    /// Enough for any table; a full sweep of ~340 processes costs about 2 ms.
    public static let limit = 100

    private let inspector: any ProcessInspecting
    private let clock: any WallClock
    private let ownUID: uid_t
    private var previous: [Int32: (cpuSeconds: Double, startTime: UInt64)] = [:]
    private var previousTime: Date?

    public init(inspector: any ProcessInspecting = LibprocInspector(), clock: any WallClock = SystemClock(), ownUID: uid_t = getuid()) {
        self.inspector = inspector
        self.clock = clock
        self.ownUID = ownUID
    }

    public func sample() -> [ProcessEntry]? {
        let now = clock.now
        let elapsed = previousTime.map { now.timeIntervalSince($0) } ?? 0
        defer { previousTime = now }

        var entries: [ProcessEntry] = []
        var current: [Int32: (cpuSeconds: Double, startTime: UInt64)] = [:]
        for pid in inspector.allProcessIDs() {
            guard let detail = inspector.details(of: pid) else { continue }
            current[pid] = (detail.cpuSeconds, detail.identity.startTime)

            var percent = 0.0
            if elapsed > 0, let last = previous[pid], last.startTime == detail.identity.startTime,
               detail.cpuSeconds >= last.cpuSeconds {
                percent = (detail.cpuSeconds - last.cpuSeconds) / elapsed * 100
            }
            entries.append(ProcessEntry(
                pid: pid,
                name: detail.name,
                cpuPercent: percent,
                memoryBytes: detail.memoryBytes,
                threads: detail.threads,
                isOwn: detail.uid == ownUID
            ))
        }
        previous = current
        guard elapsed > 0 else { return [] } // first pass only sets the baseline
        return Array(entries.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(Self.limit))
    }
}
```

`Sources/EyesUpCore/Metrics/Probes/AssertionProbe.swift`:
```swift
import Foundation

/// Which *other* apps are keeping the Mac awake (spec §6.2) — the answer to "why won't it sleep?"
public struct AssertionProbe {
    private let ownPID: Int32

    public init(ownPID: Int32 = getpid()) {
        self.ownPID = ownPID
    }

    public func sample() -> [OtherAssertion]? {
        let relevant: Set<String> = [
            AssertionKind.preventDisplaySleep.ioKitType,
            AssertionKind.preventIdleSystemSleep.ioKitType,
            AssertionKind.preventSystemSleep.ioKitType,
        ]
        let inspector = LibprocInspector()
        var seen: Set<OtherAssertion> = []
        for assertion in SystemAssertions.all() where assertion.pid != ownPID && relevant.contains(assertion.type) {
            let name = inspector.name(of: assertion.pid) ?? "process \(assertion.pid)"
            seen.insert(OtherAssertion(processName: name, type: assertion.type))
        }
        return Array(seen).sorted { $0.processName.localizedCaseInsensitiveCompare($1.processName) == .orderedAscending }
    }
}
```

- [ ] **Step 5: Write process control**

`Sources/EyesUpCore/Processes/ProcessControl.swift`:
```swift
import Darwin
import Foundation

public enum ProcessControlError: Error, Equatable, Sendable {
    case notYours
    case gone
    case recycled

    public var message: String {
        switch self {
        case .notYours: "That process belongs to another user, so EyesUpGuardian can't quit it."
        case .gone: "That process has already ended."
        case .recycled: "That process ended and its ID now belongs to something else, so nothing was quit."
        }
    }
}

/// Sending signals, behind a protocol so tests never signal a real process.
public protocol ProcessSignalling: Sendable {
    func send(_ signal: Int32, to pid: Int32) -> Bool
}

public struct POSIXSignaller: ProcessSignalling {
    public init() {}

    public func send(_ signal: Int32, to pid: Int32) -> Bool {
        pid > 0 && kill(pid, signal) == 0
    }
}

/// Quit / Force Quit for the user's own processes only (spec §7.3, §9.6).
/// The identity is re-verified immediately before the signal, so a recycled PID is never hit.
public struct ProcessControl {
    private let inspector: any ProcessInspecting
    private let ownUID: uid_t
    private let signaller: any ProcessSignalling

    public init(
        inspector: any ProcessInspecting = LibprocInspector(),
        ownUID: uid_t = getuid(),
        signaller: any ProcessSignalling = POSIXSignaller()
    ) {
        self.inspector = inspector
        self.ownUID = ownUID
        self.signaller = signaller
    }

    public func quit(_ identity: ProcessIdentity, force: Bool) throws {
        guard let current = inspector.identity(of: identity.pid) else { throw ProcessControlError.gone }
        guard current == identity else { throw ProcessControlError.recycled }
        guard let uid = inspector.ownerUID(of: identity.pid), uid == ownUID else { throw ProcessControlError.notYours }
        _ = signaller.send(force ? SIGKILL : SIGTERM, to: identity.pid)
    }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `make test`
Expected: all 6 `ProcessControlTests` pass, and Plan 1/2 process tests stay green.

- [ ] **Step 7: Commit**

```bash
git add Sources/EyesUpCore Tests/EyesUpCoreTests
git commit -m "feat(core): add process metrics, other-app assertions and safe quit" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: MetricsCenter — subscriptions, cadence and history

**Files:**
- Create: `Sources/EyesUpCore/Metrics/MetricsExecutor.swift`, `Sources/EyesUpCore/Metrics/MetricsCenter.swift`, `Sources/EyesUpCore/Metrics/Probes/LiveProbes.swift`, `Tests/EyesUpCoreTests/MetricsCenterTests.swift`
- Modify: `Sources/EyesUpApp/AppEnvironment.swift` (own the center)

**Interfaces:**
- Consumes: every probe from Tasks 2–5, `WallClock`, `TimerScheduling`, `ScheduledTask`.
- Produces:
  - `protocol MetricsProbing: Sendable { func sample(_ ids: Set<MetricID>) -> MetricsSnapshot; func resetBaselines() }`
  - `protocol MetricsExecuting: Sendable { func run(_ work: @escaping @Sendable () -> MetricsSnapshot, completion: @escaping @MainActor (MetricsSnapshot) -> Void) }`, `struct InlineExecutor`, `struct BackgroundExecutor`
  - `@MainActor @Observable final class MetricsCenter`: `snapshot`, `init(probes:executor:clock:scheduler:)`, `subscribe(_ ids: Set<MetricID>, interval: TimeInterval) -> MetricsSubscription`, `history(_ id: MetricID) -> [Double]`, `refresh()`, `isSampling`, `static historyLength = 300`
  - `final class MetricsSubscription { func cancel() }`
  - `final class LiveProbes: MetricsProbing`

- [ ] **Step 1: Write the failing tests**

`Tests/EyesUpCoreTests/MetricsCenterTests.swift`:
```swift
import Foundation
import Testing
@testable import EyesUpCore

@Suite @MainActor struct MetricsCenterTests {
    let clock = FakeClock()
    let scheduler = FakeScheduler()
    let probes = FakeProbes()

    func makeCenter() -> MetricsCenter {
        MetricsCenter(probes: probes, executor: InlineExecutor(), clock: clock, scheduler: scheduler)
    }

    @Test func noTimerWhenNothingIsSubscribed() {
        let center = makeCenter()
        #expect(!center.isSampling)
        #expect(scheduler.pending.isEmpty)
        #expect(probes.sampleCount == 0)
    }

    @Test func subscribingSamplesAtOnceAndThenOnItsInterval() {
        let center = makeCenter()
        let subscription = center.subscribe([.cpu], interval: 1)
        #expect(probes.sampleCount == 1)
        #expect(center.snapshot.cpu?.total == 25)

        clock.advance(1)
        scheduler.runDue(at: clock.now)
        #expect(probes.sampleCount == 2)
        subscription.cancel()
    }

    @Test func samplesOnlyTheUnionOfSubscribedMetrics() {
        let center = makeCenter()
        let first = center.subscribe([.cpu], interval: 1)
        let second = center.subscribe([.memory, .power], interval: 5)
        #expect(probes.lastRequested == [.cpu, .memory, .power])

        second.cancel()
        clock.advance(1)
        scheduler.runDue(at: clock.now)
        #expect(probes.lastRequested == [.cpu])
        first.cancel()
    }

    @Test func theFastestIntervalWins() {
        let center = makeCenter()
        let slow = center.subscribe([.cpu], interval: 10)
        let fast = center.subscribe([.memory], interval: 1)
        #expect(scheduler.pending.map(\.date).min() == referenceDate.addingTimeInterval(1))
        fast.cancel()
        clock.advance(1)
        scheduler.runDue(at: clock.now)
        #expect(scheduler.pending.map(\.date).min() == referenceDate.addingTimeInterval(11))
        slow.cancel()
    }

    @Test func stopsSamplingWhenTheLastSubscriberGoesAway() {
        let center = makeCenter()
        let subscription = center.subscribe([.cpu], interval: 1)
        subscription.cancel()
        #expect(!center.isSampling)
        #expect(scheduler.pending.isEmpty)

        let countAfterCancel = probes.sampleCount
        clock.advance(60)
        scheduler.runDue(at: clock.now)
        #expect(probes.sampleCount == countAfterCancel)
    }

    @Test func historyKeepsTheLastValuesAndNoMore() {
        let center = makeCenter()
        let subscription = center.subscribe([.cpu], interval: 1)
        for step in 1...(MetricsCenter.historyLength + 20) {
            probes.cpuTotal = Double(step % 100)
            clock.advance(1)
            scheduler.runDue(at: clock.now)
        }
        #expect(center.history(.cpu).count == MetricsCenter.historyLength)
        #expect(center.history(.cpu).last == center.snapshot.cpu?.total)
        #expect(center.history(.memory).isEmpty)
        subscription.cancel()
    }

    @Test func aFailingProbeLeavesOtherMetricsIntact() {
        let center = makeCenter()
        let subscription = center.subscribe([.cpu, .power], interval: 1)
        #expect(center.snapshot.power?.watts == 40)

        probes.powerAvailable = false
        clock.advance(1)
        scheduler.runDue(at: clock.now)
        #expect(center.snapshot.power == nil)     // the stat blanks
        #expect(center.snapshot.cpu != nil)       // its neighbours keep working
        subscription.cancel()
    }

    @Test func refreshDropsStaleBaselines() {
        let center = makeCenter()
        let subscription = center.subscribe([.network], interval: 1)
        center.refresh()
        #expect(probes.resetCount == 1)
        #expect(probes.sampleCount == 2) // refresh re-samples immediately
        subscription.cancel()
    }
}
```

Append to `Tests/EyesUpCoreTests/Support/TriggerFakes.swift`:
```swift
final class FakeProbes: MetricsProbing, @unchecked Sendable {
    var cpuTotal = 25.0
    var powerAvailable = true
    private(set) var sampleCount = 0
    private(set) var resetCount = 0
    private(set) var lastRequested: Set<MetricID> = []

    func sample(_ ids: Set<MetricID>) -> MetricsSnapshot {
        sampleCount += 1
        lastRequested = ids
        var snapshot = MetricsSnapshot()
        if ids.contains(.cpu) {
            snapshot.cpu = CPUMetrics(total: cpuTotal, cores: [cpuTotal], performance: nil, efficiency: nil)
        }
        if ids.contains(.memory) {
            snapshot.memory = MemoryMetrics(usedBytes: 1, appBytes: 1, wiredBytes: 1, compressedBytes: 0,
                                            totalBytes: 2, swapUsedBytes: 0, pressure: .normal)
        }
        if ids.contains(.power), powerAvailable { snapshot.power = PowerMetrics(watts: 40) }
        if ids.contains(.network) { snapshot.network = NetworkMetrics(inBytesPerSecond: 1, outBytesPerSecond: 1) }
        return snapshot
    }

    func resetBaselines() { resetCount += 1 }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test`
Expected: FAIL to compile with `cannot find type 'MetricsProbing' in scope`.

- [ ] **Step 3: Write the executor**

`Sources/EyesUpCore/Metrics/MetricsExecutor.swift`:
```swift
import Foundation

/// Everything the center can read. A probe that can't read its source leaves that slot nil.
public protocol MetricsProbing: Sendable {
    func sample(_ ids: Set<MetricID>) -> MetricsSnapshot
    /// Counters jumped (the Mac slept): drop rate baselines instead of reporting a fake burst.
    func resetBaselines()
}

/// Where sampling runs. Production uses a background queue; tests run inline and deterministically.
public protocol MetricsExecuting: Sendable {
    func run(_ work: @escaping @Sendable () -> MetricsSnapshot, completion: @escaping @MainActor (MetricsSnapshot) -> Void)
}

public struct InlineExecutor: MetricsExecuting {
    public init() {}

    public func run(_ work: @escaping @Sendable () -> MetricsSnapshot, completion: @escaping @MainActor (MetricsSnapshot) -> Void) {
        let snapshot = work()
        MainActor.assumeIsolated { completion(snapshot) }
    }
}

/// One serial queue for every sample, so probing never blocks the UI (spec §2 data flow).
public struct BackgroundExecutor: MetricsExecuting {
    private let queue = DispatchQueue(label: "dev.eyesupguardian.metrics", qos: .utility)

    public init() {}

    public func run(_ work: @escaping @Sendable () -> MetricsSnapshot, completion: @escaping @MainActor (MetricsSnapshot) -> Void) {
        queue.async {
            let snapshot = work()
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(snapshot) } }
        }
    }
}
```

- [ ] **Step 4: Write the center**

`Sources/EyesUpCore/Metrics/MetricsCenter.swift`:
```swift
import Foundation
import Observation

/// A surface's claim on some metrics. Cancelling it stops that surface's sampling.
@MainActor
public final class MetricsSubscription {
    let id = UUID()
    let ids: Set<MetricID>
    let interval: TimeInterval
    private weak var center: MetricsCenter?

    init(ids: Set<MetricID>, interval: TimeInterval, center: MetricsCenter) {
        self.ids = ids
        self.interval = interval
        self.center = center
    }

    public func cancel() {
        center?.remove(self)
        center = nil
    }

    // No deinit: `deinit` is not main-actor isolated, and hopping there from one would either trap or
    // race. Every surface cancels explicitly in `onDisappear`, and Task 8's tests pin that.
}

/// Samples the union of what's subscribed, at the fastest interval asked for, and nothing at all
/// when nobody is looking (spec §3.1, §6.1).
@MainActor
@Observable
public final class MetricsCenter {
    /// Five minutes of 1 s samples (spec §3.4).
    public static let historyLength = 300

    public private(set) var snapshot = MetricsSnapshot()

    public var isSampling: Bool { !subscriptions.isEmpty }

    @ObservationIgnored private let probes: any MetricsProbing
    @ObservationIgnored private let executor: any MetricsExecuting
    @ObservationIgnored private let clock: any WallClock
    @ObservationIgnored private let scheduler: any TimerScheduling
    @ObservationIgnored private var subscriptions: [UUID: (ids: Set<MetricID>, interval: TimeInterval)] = [:]
    @ObservationIgnored private var histories: [MetricID: [Double]] = [:]
    @ObservationIgnored private var task: (any ScheduledTask)?

    public init(
        probes: any MetricsProbing,
        executor: any MetricsExecuting = BackgroundExecutor(),
        clock: any WallClock = SystemClock(),
        scheduler: any TimerScheduling
    ) {
        self.probes = probes
        self.executor = executor
        self.clock = clock
        self.scheduler = scheduler
    }

    public func subscribe(_ ids: Set<MetricID>, interval: TimeInterval) -> MetricsSubscription {
        let subscription = MetricsSubscription(ids: ids, interval: max(0.5, interval), center: self)
        subscriptions[subscription.id] = (ids, subscription.interval)
        sampleNow()
        return subscription
    }

    /// The recent history of a metric's headline number, oldest first.
    public func history(_ id: MetricID) -> [Double] {
        histories[id] ?? []
    }

    /// After a wake or a clock change: drop stale baselines and take a fresh sample.
    public func refresh() {
        probes.resetBaselines()
        histories.removeAll()
        sampleNow()
    }

    func remove(_ subscription: MetricsSubscription) {
        remove(subscriptionID: subscription.id)
    }

    func remove(subscriptionID: UUID) {
        subscriptions[subscriptionID] = nil
        if subscriptions.isEmpty {
            task?.cancel()
            task = nil
        } else {
            rearm()
        }
    }

    private var requestedIDs: Set<MetricID> {
        subscriptions.values.reduce(into: Set<MetricID>()) { $0.formUnion($1.ids) }
    }

    private var interval: TimeInterval {
        subscriptions.values.map(\.interval).min() ?? 1
    }

    private func sampleNow() {
        task?.cancel()
        task = nil
        let ids = requestedIDs
        guard !ids.isEmpty else { return }

        let probes = probes
        executor.run({ probes.sample(ids) }) { [weak self] fresh in
            self?.apply(fresh, requested: ids)
        }
        rearm()
    }

    private func rearm() {
        task?.cancel()
        guard !subscriptions.isEmpty else {
            task = nil
            return
        }
        task = scheduler.schedule(at: clock.now.addingTimeInterval(interval)) { [weak self] in self?.sampleNow() }
    }

    private func apply(_ fresh: MetricsSnapshot, requested: Set<MetricID>) {
        // Metrics we asked for but didn't get are unavailable now, so they blank instead of going stale.
        var merged = snapshot
        for id in requested { merged.clear(id) }
        snapshot = merged.merging(fresh)
        record(fresh)
    }

    private func record(_ fresh: MetricsSnapshot) {
        var values: [MetricID: Double] = [:]
        if let cpu = fresh.cpu { values[.cpu] = cpu.total }
        if let memory = fresh.memory, memory.totalBytes > 0 {
            values[.memory] = Double(memory.usedBytes) / Double(memory.totalBytes) * 100
        }
        if let power = fresh.power { values[.power] = power.watts }
        if let gpu = fresh.gpu { values[.gpu] = gpu.utilization }
        if let temperature = fresh.temperature { values[.temperature] = temperature.celsius }
        if let network = fresh.network { values[.network] = (network.inBytesPerSecond ?? 0) + (network.outBytesPerSecond ?? 0) }
        if let storage = fresh.storage {
            values[.storage] = (storage.readBytesPerSecond ?? 0) + (storage.writeBytesPerSecond ?? 0)
        }
        for (id, value) in values {
            var series = histories[id] ?? []
            series.append(value)
            if series.count > Self.historyLength { series.removeFirst(series.count - Self.historyLength) }
            histories[id] = series
        }
    }
}

extension MetricsSnapshot {
    /// Used by the center to blank a metric that was requested but came back empty.
    mutating func clear(_ id: MetricID) {
        switch id {
        case .cpu: cpu = nil
        case .memory: memory = nil
        case .system: system = nil
        case .storage: storage = nil
        case .network: network = nil
        case .processes: processes = nil
        case .power: power = nil
        case .fans: fans = nil
        case .temperature: temperature = nil
        case .gpu: gpu = nil
        case .otherAssertions: otherAssertions = nil
        }
    }
}
```

- [ ] **Step 5: Compose the live probes**

`Sources/EyesUpCore/Metrics/Probes/LiveProbes.swift`:
```swift
import Foundation

/// Every real probe behind one `MetricsProbing`. Sampling happens off the main thread, so the
/// mutable probe state is guarded by a lock rather than an actor.
public final class LiveProbes: MetricsProbing, @unchecked Sendable {
    private let lock = NSLock()
    private let cpu = CPUProbe()
    private let memory = MemoryProbe()
    private let system = SystemProbe()
    private let storage: StorageProbe
    private let network: NetworkProbe
    private let processes: ProcessProbe
    private let assertions = AssertionProbe()
    private let gpu = GPUProbe()
    private let smc: SMCProbe?

    public init(counters: any SystemCounters = LiveSystemCounters(), clock: any WallClock = SystemClock()) {
        storage = StorageProbe(counters: counters, clock: clock)
        network = NetworkProbe(counters: counters, clock: clock)
        processes = ProcessProbe(clock: clock)
        smc = SMC().map { SMCProbe(smc: $0) }
    }

    public func sample(_ ids: Set<MetricID>) -> MetricsSnapshot {
        lock.lock()
        defer { lock.unlock() }

        var snapshot = MetricsSnapshot()
        if ids.contains(.cpu) { snapshot.cpu = cpu.sample() }
        if ids.contains(.memory) { snapshot.memory = memory.sample() }
        if ids.contains(.system) { snapshot.system = system.sample() }
        if ids.contains(.storage) { snapshot.storage = storage.sample() }
        if ids.contains(.network) { snapshot.network = network.sample() }
        if ids.contains(.processes) { snapshot.processes = processes.sample() }
        if ids.contains(.gpu) { snapshot.gpu = gpu.sample() }
        if ids.contains(.otherAssertions) { snapshot.otherAssertions = assertions.sample() }
        if ids.contains(.power) { snapshot.power = smc?.power() }
        if ids.contains(.fans) { snapshot.fans = smc?.fans() }
        if ids.contains(.temperature) { snapshot.temperature = smc?.temperature() }
        return snapshot
    }

    public func resetBaselines() {
        lock.lock()
        defer { lock.unlock() }
        storage.resetBaseline()
        network.resetBaseline()
    }
}
```

- [ ] **Step 6: Give the app a center**

In `Sources/EyesUpApp/AppEnvironment.swift`:
1. Add a property beside the others: `let metrics: MetricsCenter`.
2. In `init()`, after the engine is built: `metrics = MetricsCenter(probes: LiveProbes(), scheduler: scheduler)`.
3. In the `refresh` closure inside `start()`, add `self?.metrics.refresh()` after `self?.engine.refresh()`.

- [ ] **Step 7: Run the tests and check the idle budget**

Run: `make test`
Expected: all 8 `MetricsCenterTests` pass.
Run: `make app && make perf`
Expected: `PASS`. Nothing subscribes yet, so the center must not sample at all.

- [ ] **Step 8: Commit**

```bash
git add Sources Tests
git commit -m "feat(core): add the metrics center with on-demand sampling and history" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 7: Stat formatting

**Files:**
- Create: `Sources/EyesUpCore/Formatting/StatFormatting.swift`, `Tests/EyesUpCoreTests/StatFormattingTests.swift`

**Interfaces:**
- Produces `enum StatFormatting` with `bytes(_:)`, `rate(_:)`, `percent(_:)`, `watts(_:)`, `celsius(_:)`, `rpm(_:)`, `uptime(since:now:)`, `idle(_:)`, and `unavailable = "—"`. Every function takes an optional and returns `unavailable` for nil, NaN or infinity.

- [ ] **Step 1: Write the failing tests**

`Tests/EyesUpCoreTests/StatFormattingTests.swift`:
```swift
import Foundation
import Testing
@testable import EyesUpCore

@Suite struct StatFormattingTests {
    @Test func bytesUseTheRightUnit() {
        #expect(StatFormatting.bytes(512) == "512 B")
        #expect(StatFormatting.bytes(2048) == "2.0 KB")
        #expect(StatFormatting.bytes(5_500_000) == "5.5 MB")
        #expect(StatFormatting.bytes(41_000_000_000) == "41.0 GB")
        #expect(StatFormatting.bytes(2_500_000_000_000) == "2.5 TB")
    }

    @Test func ratesReadPerSecond() {
        #expect(StatFormatting.rate(0) == "0 B/s")
        #expect(StatFormatting.rate(1_500_000) == "1.5 MB/s")
    }

    @Test func percentsAndUnitsAreShort() {
        #expect(StatFormatting.percent(12.4) == "12%")
        #expect(StatFormatting.percent(99.6) == "100%")
        #expect(StatFormatting.watts(38.44) == "38.4 W")
        #expect(StatFormatting.celsius(57.91) == "58°C")
        #expect(StatFormatting.rpm(996) == "996 rpm")
    }

    @Test func uptimeReadsInDaysAndHours() {
        let now = referenceDate
        #expect(StatFormatting.uptime(since: now.addingTimeInterval(-90), now: now) == "1m")
        #expect(StatFormatting.uptime(since: now.addingTimeInterval(-3 * 3600 - 600), now: now) == "3h 10m")
        #expect(StatFormatting.uptime(since: now.addingTimeInterval(-(6 * 86_400 + 4 * 3600)), now: now) == "6d 4h")
        #expect(StatFormatting.uptime(since: now.addingTimeInterval(60), now: now) == StatFormatting.unavailable)
    }

    @Test func idleReadsAsAwayTime() {
        #expect(StatFormatting.idle(5) == "just now")
        #expect(StatFormatting.idle(2520) == "42m")
    }

    @Test func formattersHandleMissingAndAbsurdValues() {
        #expect(StatFormatting.percent(nil) == StatFormatting.unavailable)
        #expect(StatFormatting.percent(.nan) == StatFormatting.unavailable)
        #expect(StatFormatting.watts(.infinity) == StatFormatting.unavailable)
        #expect(StatFormatting.bytes(nil) == StatFormatting.unavailable)
        #expect(StatFormatting.rate(-5) == StatFormatting.unavailable)
        #expect(StatFormatting.celsius(nil) == StatFormatting.unavailable)
        #expect(StatFormatting.rpm(.nan) == StatFormatting.unavailable)
        #expect(StatFormatting.idle(nil) == StatFormatting.unavailable)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test`
Expected: FAIL to compile with `cannot find 'StatFormatting' in scope`.

- [ ] **Step 3: Write the formatters**

`Sources/EyesUpCore/Formatting/StatFormatting.swift`:
```swift
import Foundation

/// Short, honest stat text. Anything missing or nonsensical reads as "—" rather than a fake number.
public enum StatFormatting {
    public static let unavailable = "—"

    public static func bytes(_ value: UInt64?) -> String {
        guard let value else { return unavailable }
        let units: [(threshold: Double, suffix: String)] = [
            (1_000_000_000_000, "TB"), (1_000_000_000, "GB"), (1_000_000, "MB"), (1000, "KB"),
        ]
        let amount = Double(value)
        for unit in units where amount >= unit.threshold {
            return String(format: "%.1f %@", amount / unit.threshold, unit.suffix)
        }
        return "\(value) B"
    }

    public static func rate(_ bytesPerSecond: Double?) -> String {
        guard let value = bytesPerSecond, value.isFinite, value >= 0 else { return unavailable }
        guard value >= 1000 else { return "\(Int(value)) B/s" }
        return bytes(UInt64(min(value, Double(UInt64.max)))) + "/s"
    }

    public static func percent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return unavailable }
        return "\(Int(min(max(value, 0), 100).rounded()))%"
    }

    public static func watts(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return unavailable }
        return String(format: "%.1f W", value)
    }

    public static func celsius(_ value: Double?) -> String {
        guard let value, value.isFinite else { return unavailable }
        return "\(Int(value.rounded()))°C"
    }

    public static func rpm(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return unavailable }
        return "\(Int(value.rounded())) rpm"
    }

    /// "6d 4h", "3h 10m", "42m".
    public static func uptime(since bootTime: Date?, now: Date = Date()) -> String {
        guard let bootTime, now > bootTime else { return unavailable }
        let total = Int(now.timeIntervalSince(bootTime))
        let days = total / 86_400
        let hours = (total % 86_400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(max(minutes, 1))m"
    }

    public static func idle(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return unavailable }
        guard seconds >= 60 else { return "just now" }
        return TimeFormatting.duration(seconds)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `make test`
Expected: all 6 `StatFormattingTests` pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/EyesUpCore/Formatting/StatFormatting.swift Tests/EyesUpCoreTests/StatFormattingTests.swift
git commit -m "feat(core): add stat formatting that never prints a fake number" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 8: Popover stat tiles

**Files:**
- Create: `Sources/EyesUpApp/Stats/StatTile.swift`, `Sources/EyesUpApp/Stats/StatsViewModel.swift`, `Tests/EyesUpAppTests/StatViewModelTests.swift`
- Modify: `Sources/EyesUpApp/Popover/PopoverView.swift` (four tiles + the other-apps row)
- Modify: `Sources/EyesUpApp/EyesUpGuardianApp.swift` (hand the center to the popover)

**Interfaces:**
- Consumes: `MetricsCenter`, `MetricsSubscription`, `StatFormatting`, `MetricsSnapshot`.
- Produces:
  - `struct StatTile: View` (`init(title:value:detail:symbol:)`)
  - `@MainActor @Observable final class StatsViewModel`: `init(center:ids:interval:)`, `snapshot`, `start()`, `stop()`, `var tiles: [StatTileModel]`, `struct StatTileModel: Identifiable { title, value, detail, symbol }`
  - `PopoverView(controller:onOpenDashboard:form:stats:)`

The view model is what makes "sampling stops when the window closes" testable: `start()` subscribes, `stop()` cancels, and the popover calls them from `onAppear`/`onDisappear`.

- [ ] **Step 1: Write the failing tests**

`Tests/EyesUpAppTests/StatViewModelTests.swift`:
```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test`
Expected: FAIL to compile with `cannot find 'StatsViewModel' in scope`.

- [ ] **Step 3: Write the view model and tile**

`Sources/EyesUpApp/Stats/StatsViewModel.swift`:
```swift
import EyesUpCore
import Foundation
import Observation

/// One surface's claim on the metrics it displays. `start()` on appear, `stop()` on disappear —
/// that is what keeps sampling tied to what's actually visible (spec §6.1).
@MainActor
@Observable
final class StatsViewModel {
    struct StatTileModel: Identifiable {
        let id: String
        let title: String
        let value: String
        let detail: String
        let symbol: String
    }

    private let center: MetricsCenter
    private let ids: Set<MetricID>
    private let interval: TimeInterval
    @ObservationIgnored private var subscription: MetricsSubscription?

    init(center: MetricsCenter, ids: Set<MetricID>, interval: TimeInterval) {
        self.center = center
        self.ids = ids
        self.interval = interval
    }

    var snapshot: MetricsSnapshot { center.snapshot }

    func history(_ id: MetricID) -> [Double] { center.history(id) }

    func start() {
        guard subscription == nil else { return }
        subscription = center.subscribe(ids, interval: interval)
    }

    func stop() {
        subscription?.cancel()
        subscription = nil
    }

    /// The popover's four tiles: CPU, memory, power (temperature when watts aren't readable), uptime.
    var tiles: [StatTileModel] {
        let snapshot = center.snapshot
        let memoryPercent = snapshot.memory.map { $0.totalBytes > 0 ? Double($0.usedBytes) / Double($0.totalBytes) * 100 : 0 }
        let powerTile: StatTileModel = if snapshot.power != nil || snapshot.temperature == nil {
            StatTileModel(id: "power", title: "Power", value: StatFormatting.watts(snapshot.power?.watts),
                          detail: "system", symbol: "bolt")
        } else {
            StatTileModel(id: "temperature", title: "Temp", value: StatFormatting.celsius(snapshot.temperature?.celsius),
                          detail: "hottest sensor", symbol: "thermometer.medium")
        }
        return [
            StatTileModel(id: "cpu", title: "CPU", value: StatFormatting.percent(snapshot.cpu?.total),
                          detail: snapshot.cpu.map { "\($0.cores.count) cores" } ?? "", symbol: "cpu"),
            StatTileModel(id: "memory", title: "Memory", value: StatFormatting.percent(memoryPercent),
                          detail: StatFormatting.bytes(snapshot.memory?.usedBytes), symbol: "memorychip"),
            powerTile,
            StatTileModel(id: "uptime", title: "Uptime", value: StatFormatting.uptime(since: snapshot.system?.bootTime),
                          detail: "since boot", symbol: "clock.arrow.circlepath"),
        ]
    }
}
```

`Sources/EyesUpApp/Stats/StatTile.swift`:
```swift
import SwiftUI

/// One number in a glass tile: used by the popover, the Overview tab and the HUD.
struct StatTile: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: symbol)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
            if !detail.isEmpty {
                Text(detail).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value) \(detail)")
    }
}
```

- [ ] **Step 4: Put the tiles in the popover**

In `Sources/EyesUpApp/Popover/PopoverView.swift`:

1. Add a stored property **after `form`**, so the memberwise initializer's argument order stays
   `controller, onOpenDashboard, form, stats` and matches the call site below:
```swift
    let stats: StatsViewModel
```
2. Add the tiles and the warning row to `body`, right before `messages`:
```swift
                statTiles
                otherAppsWarning
```
3. Add these two views next to the other sections:
```swift
    private var statTiles: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
            ForEach(stats.tiles) { tile in
                StatTile(title: tile.title, value: tile.value, detail: tile.detail, symbol: tile.symbol)
            }
        }
    }

    /// Spec §7.2: say when something *else* is the reason the Mac won't sleep.
    @ViewBuilder
    private var otherAppsWarning: some View {
        if let others = stats.snapshot.otherAssertions, !others.isEmpty {
            let names = Set(others.map(\.processName)).sorted().prefix(3).joined(separator: ", ")
            Label("\(names) \(others.count == 1 ? "is" : "are") also keeping your Mac awake",
                  systemImage: "exclamationmark.bubble")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
```
4. Make the popover start and stop sampling by adding these modifiers after `.background(AmbientBackground(...))`:
```swift
        .onAppear { stats.start() }
        .onDisappear { stats.stop() }
```

In `Sources/EyesUpApp/EyesUpGuardianApp.swift`, pass the model when building the popover:
```swift
        statusItem.setPopoverContent(PopoverView(
            controller: environment.controller,
            onOpenDashboard: { dashboard.show() },
            form: PopoverFormState(),
            stats: StatsViewModel(center: environment.metrics,
                                  ids: [.cpu, .memory, .power, .temperature, .system, .otherAssertions],
                                  interval: 1)
        ))
```

- [ ] **Step 5: Run the tests and look at it**

Run: `make test && make app`
Expected: the 3 `StatViewModelTests` pass and the app builds with no warnings.
Run: `open build/EyesUpGuardian.app`, click the menu-bar ring.
Expected: four tiles — CPU, Memory, Power (watts on this Mac), Uptime — updating about once a second. With the popover closed, Activity Monitor should show EyesUpGuardian back at ~0% CPU.

- [ ] **Step 6: Commit**

```bash
git add Sources/EyesUpApp Tests/EyesUpAppTests
git commit -m "feat(app): add live stat tiles and the other-apps warning to the popover" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 9: Overview tab

**Files:**
- Create: `Sources/EyesUpApp/Stats/Sparkline.swift`, `Sources/EyesUpApp/Dashboard/OverviewTab.swift`
- Modify: `Sources/EyesUpApp/Dashboard/DashboardWindow.swift` (add the tab)

**Interfaces:**
- Consumes: `StatsViewModel`, `StatTile`, `StatFormatting`, `MetricsCenter.history(_:)`, `AmbientBackground`.
- Produces: `struct Sparkline: View` (`init(values:tint:)`), `struct OverviewTab: View` (`init(environment:)`), `DashboardState.Tab.overview` as the first tab.

- [ ] **Step 1: Write the sparkline**

`Sources/EyesUpApp/Stats/Sparkline.swift`:
```swift
import SwiftUI

/// A tiny history chart. Draws nothing when there's no history yet, so it never implies data it lacks.
struct Sparkline: View {
    let values: [Double]
    var tint: Color = .orange

    var body: some View {
        GeometryReader { geometry in
            if values.count > 1 {
                let highest = max(values.max() ?? 1, 0.0001)
                let step = geometry.size.width / CGFloat(values.count - 1)
                let points = values.enumerated().map { index, value in
                    CGPoint(
                        x: CGFloat(index) * step,
                        y: geometry.size.height * (1 - CGFloat(min(max(value / highest, 0), 1)))
                    )
                }
                Path { path in
                    path.move(to: points[0])
                    for point in points.dropFirst() { path.addLine(to: point) }
                }
                .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                Path { path in
                    path.move(to: CGPoint(x: 0, y: geometry.size.height))
                    for point in points { path.addLine(to: point) }
                    path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
                    path.closeSubpath()
                }
                .fill(LinearGradient(colors: [tint.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
            }
        }
        .frame(height: 32)
        .accessibilityHidden(true)
    }
}
```

- [ ] **Step 2: Write the Overview tab**

`Sources/EyesUpApp/Dashboard/OverviewTab.swift`:
```swift
import EyesUpCore
import SwiftUI

/// The Ambient overview: what the Mac is doing right now, and why it's awake.
struct OverviewTab: View {
    let environment: AppEnvironment
    @Bindable var stats: StatsViewModel

    private var snapshot: MetricsSnapshot { stats.snapshot }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headline
                headlineCharts
                tiles
                otherApps
            }
            .padding(20)
        }
        .onAppear { stats.start() }
        .onDisappear { stats.stop() }
    }

    private var headline: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 4) {
                Text(environment.controller.isAwake ? "Awake" : "Your Mac may sleep")
                    .font(.callout).foregroundStyle(.secondary)
                Text(countdown(now: context.date))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if environment.controller.isAwake {
                    Text(environment.controller.holds.map(\.label).joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
    }

    private func countdown(now: Date) -> String {
        guard environment.controller.isAwake else { return "Idle" }
        guard let until = environment.controller.awakeUntil else { return "No end time" }
        return TimeFormatting.countdown(until.timeIntervalSince(now))
    }

    private var headlineCharts: some View {
        HStack(spacing: 12) {
            chart("CPU", StatFormatting.percent(snapshot.cpu?.total), stats.history(.cpu), .orange)
            chart("Memory", StatFormatting.bytes(snapshot.memory?.usedBytes), stats.history(.memory), .purple)
            chart("Power", StatFormatting.watts(snapshot.power?.watts), stats.history(.power), .yellow)
        }
    }

    private func chart(_ title: String, _ value: String, _ history: [Double], _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit().contentTransition(.numericText())
            Sparkline(values: history, tint: tint)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }

    private var tiles: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
            StatTile(title: "GPU", value: StatFormatting.percent(snapshot.gpu?.utilization), detail: "utilization", symbol: "cpu.fill")
            StatTile(title: "Temperature", value: StatFormatting.celsius(snapshot.temperature?.celsius),
                     detail: snapshot.temperature.map { "hottest of \($0.sensorCount) sensors" } ?? "not available", symbol: "thermometer.medium")
            StatTile(title: "Fans", value: fanValue, detail: fanDetail, symbol: "fan")
            StatTile(title: "Performance cores", value: StatFormatting.percent(snapshot.cpu?.performance), detail: "average", symbol: "bolt.horizontal")
            StatTile(title: "Efficiency cores", value: StatFormatting.percent(snapshot.cpu?.efficiency), detail: "average", symbol: "leaf")
            StatTile(title: "Memory pressure", value: snapshot.memory?.pressure.rawValue.capitalized ?? StatFormatting.unavailable,
                     detail: "swap " + StatFormatting.bytes(snapshot.memory?.swapUsedBytes), symbol: "gauge.with.dots.needle.50percent")
            StatTile(title: "Disk free", value: StatFormatting.bytes(snapshot.storage?.freeBytes),
                     detail: "write " + StatFormatting.rate(snapshot.storage?.writeBytesPerSecond), symbol: "internaldrive")
            StatTile(title: "Network", value: StatFormatting.rate(snapshot.network?.inBytesPerSecond),
                     detail: "up " + StatFormatting.rate(snapshot.network?.outBytesPerSecond), symbol: "network")
            StatTile(title: "Uptime", value: StatFormatting.uptime(since: snapshot.system?.bootTime), detail: "since boot", symbol: "clock.arrow.circlepath")
            StatTile(title: "Last activity", value: StatFormatting.idle(snapshot.system?.idleSeconds), detail: "keyboard or mouse", symbol: "hand.point.up.left")
            StatTile(title: "Load average", value: loadValue, detail: "1 · 5 · 15 min", symbol: "chart.line.uptrend.xyaxis")
            StatTile(title: "Thermal state", value: snapshot.system?.thermal.rawValue.capitalized ?? StatFormatting.unavailable,
                     detail: "as macOS reports it", symbol: "flame")
        }
    }

    private var fanValue: String {
        guard let fans = snapshot.fans?.fans, let fastest = fans.map(\.rpm).max() else { return StatFormatting.unavailable }
        return StatFormatting.rpm(fastest)
    }

    private var fanDetail: String {
        guard let fans = snapshot.fans?.fans, !fans.isEmpty else { return "not available" }
        let maximum = fans.compactMap(\.maxRPM).max()
        return "\(fans.count) fan\(fans.count == 1 ? "" : "s")" + (maximum.map { ", max \(Int($0))" } ?? "")
    }

    private var loadValue: String {
        guard let load = snapshot.system?.loadAverage else { return StatFormatting.unavailable }
        return String(format: "%.2f", load.0)
    }

    @ViewBuilder
    private var otherApps: some View {
        if let others = snapshot.otherAssertions, !others.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Also keeping your Mac awake").font(.headline)
                ForEach(others, id: \.self) { assertion in
                    HStack {
                        Image(systemName: "app.badge").foregroundStyle(.secondary)
                        Text(assertion.processName)
                        Spacer()
                        Text(friendly(assertion.type)).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private func friendly(_ assertionType: String) -> String {
        switch assertionType {
        case AssertionKind.preventDisplaySleep.ioKitType: "keeping the display on"
        case AssertionKind.preventIdleSystemSleep.ioKitType: "keeping the Mac awake"
        case AssertionKind.preventSystemSleep.ioKitType: "preventing all sleep"
        default: assertionType
        }
    }
}
```

- [ ] **Step 3: Add the tab**

In `Sources/EyesUpApp/Dashboard/DashboardWindow.swift`:
1. Put `overview` first in the enum: `case overview, triggers, settings`.
2. Add its title and symbol to the two switches: `case .overview: "Overview"` and `case .overview: "gauge.with.dots.needle.50percent"`.
3. Default to it: `var tab: Tab = .overview`.
4. Add a stored property to `DashboardState`:
```swift
    /// Kept for the window's lifetime so switching tabs doesn't restart sampling from scratch.
    var overviewStats: StatsViewModel?
```
5. In `DashboardView`'s detail switch, add:
```swift
                case .overview:
                    if let stats = state.overviewStats { OverviewTab(environment: environment, stats: stats) }
```
6. In `DashboardWindowController.show()`, before building the view:
```swift
        if state.overviewStats == nil {
            state.overviewStats = StatsViewModel(
                center: environment.metrics,
                ids: [.cpu, .memory, .system, .storage, .network, .power, .fans, .temperature, .gpu, .otherAssertions],
                interval: 1
            )
        }
```

- [ ] **Step 4: Build and look at it**

Run: `make test && make app && open build/EyesUpGuardian.app`
Expected: tests pass; the dashboard opens on **Overview** showing the countdown, three sparklines that fill over about 10 seconds, twelve tiles with real values (watts and fans included on this Mac), and any other apps holding the Mac awake.
Switch to Triggers, then back; the charts keep their history. Close the window and check Activity Monitor: CPU returns to ~0%.

- [ ] **Step 5: Commit**

```bash
git add Sources/EyesUpApp
git commit -m "feat(app): add the Ambient Overview tab with live charts and tiles" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 10: Menu-bar stat readout

**Files:**
- Modify: `Sources/EyesUpCore/Store/AppSettings.swift` (readout choice)
- Modify: `Sources/EyesUpApp/MenuBar/StatusItemController.swift` (draw it, subscribe at 2 s)
- Modify: `Sources/EyesUpApp/Dashboard/SettingsTab.swift` (pick it)
- Modify: `Tests/EyesUpCoreTests/SettingsTests.swift`, `Tests/EyesUpAppTests/StatViewModelTests.swift`

**Interfaces:**
- Produces:
  - `enum MenuBarReadout: String, Codable, CaseIterable, Sendable { case iconOnly, timer, timerAndCPU, timerAndPower, timerCPUAndPower }` with `var title: String`, `var metricIDs: Set<MetricID>`
  - `AppSettings.menuBarReadout: MenuBarReadout` (default `.timer`)
  - `StatusItemController.applyReadout(_:center:)`

Spec §3 allows the menu bar to sample at 2 s, and only for the stats the chosen readout shows. `.iconOnly` and `.timer` must sample nothing at all.

- [ ] **Step 1: Write the failing tests**

Append inside `@Suite @MainActor struct SettingsTests`:
```swift
    @Test func readoutDefaultsToTheTimerAndSamplesNothing() {
        #expect(AppSettings().menuBarReadout == .timer)
        #expect(MenuBarReadout.timer.metricIDs.isEmpty)
        #expect(MenuBarReadout.iconOnly.metricIDs.isEmpty)
    }

    @Test func readoutsNameTheMetricsTheyNeed() {
        #expect(MenuBarReadout.timerAndCPU.metricIDs == [.cpu])
        #expect(MenuBarReadout.timerAndPower.metricIDs == [.power])
        #expect(MenuBarReadout.timerCPUAndPower.metricIDs == [.cpu, .power])
    }

    @Test func anUnknownSavedReadoutFallsBackToTheTimer() throws {
        let data = Data(#"{"menuBarReadout":"holographic"}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(settings.menuBarReadout == .timer)
    }
```

Append inside `@Suite @MainActor struct StatViewModelTests`:
```swift
    @Test func readoutTextCombinesTheChosenStats() {
        let center = makeCenter()
        let model = StatsViewModel(center: center, ids: MenuBarReadout.timerCPUAndPower.metricIDs, interval: 2)
        model.start()
        // CPU answers, power doesn't, so only the readable part shows.
        #expect(model.readoutText(for: .timerCPUAndPower) == "20%")
        #expect(model.readoutText(for: .timerAndCPU) == "20%")
        #expect(model.readoutText(for: .timer) == "")
        model.stop()
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test`
Expected: FAIL to compile with `cannot find type 'MenuBarReadout' in scope`.

- [ ] **Step 3: Add the setting**

In `Sources/EyesUpCore/Store/AppSettings.swift`, above `AppSettings`:
```swift
/// What the menu-bar item shows beside its ring (spec §7.1).
public enum MenuBarReadout: String, Codable, CaseIterable, Sendable {
    case iconOnly, timer, timerAndCPU, timerAndPower, timerCPUAndPower

    public var title: String {
        switch self {
        case .iconOnly: "Icon only"
        case .timer: "Icon and time left"
        case .timerAndCPU: "Icon, time and CPU"
        case .timerAndPower: "Icon, time and power"
        case .timerCPUAndPower: "Icon, time, CPU and power"
        }
    }

    /// Nothing is sampled for the first two, so the menu bar costs nothing at rest.
    public var metricIDs: Set<MetricID> {
        switch self {
        case .iconOnly, .timer: []
        case .timerAndCPU: [.cpu]
        case .timerAndPower: [.power]
        case .timerCPUAndPower: [.cpu, .power]
        }
    }
}
```

Add the property to `AppSettings` (stored property, memberwise parameter, and lenient decode):
```swift
    public var menuBarReadout: MenuBarReadout
```
```swift
        menuBarReadout: MenuBarReadout = .timer,
```
```swift
        self.menuBarReadout = menuBarReadout
```
```swift
        // An unknown value from a hand-edited file falls back rather than failing the whole load.
        menuBarReadout = (try? container.decodeIfPresent(MenuBarReadout.self, forKey: .menuBarReadout)) ?? .timer
```

- [ ] **Step 4: Add readout text to the view model**

In `Sources/EyesUpApp/Stats/StatsViewModel.swift`:
```swift
    /// The menu-bar suffix, e.g. "12% · 38.4 W". Stats that aren't readable are left out entirely.
    func readoutText(for readout: MenuBarReadout) -> String {
        var parts: [String] = []
        if readout.metricIDs.contains(.cpu), let cpu = snapshot.cpu {
            parts.append(StatFormatting.percent(cpu.total))
        }
        if readout.metricIDs.contains(.power), let power = snapshot.power {
            parts.append(StatFormatting.watts(power.watts))
        }
        return parts.joined(separator: " · ")
    }
```

- [ ] **Step 5: Draw it in the menu bar**

In `Sources/EyesUpApp/MenuBar/StatusItemController.swift`:

1. Add stored properties beside `minuteTimer`:
```swift
    private var readout: MenuBarReadout = .timer
    private var stats: StatsViewModel?
    private var statsTimer: Timer?
```
2. Add the entry point the app calls when settings change:
```swift
    /// Switches the readout. Stat readouts sample every 2 s (spec §3); the other two sample nothing.
    func applyReadout(_ readout: MenuBarReadout, center: MetricsCenter) {
        self.readout = readout
        stats?.stop()
        statsTimer?.invalidate()
        statsTimer = nil

        if readout.metricIDs.isEmpty {
            stats = nil
        } else {
            let model = StatsViewModel(center: center, ids: readout.metricIDs, interval: 2)
            model.start()
            stats = model
            let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            timer.tolerance = 0.5
            RunLoop.main.add(timer, forMode: .common)
            statsTimer = timer
        }
        refresh()
    }
```
3. In `refresh()`, replace the `button.title` assignment with:
```swift
        var title = readout == .iconOnly ? "" : (until.map { " " + TimeFormatting.menuBar(remaining: $0.timeIntervalSince(now)) } ?? "")
        if let stats, case let text = stats.readoutText(for: readout), !text.isEmpty {
            title += title.isEmpty ? " " + text : " · " + text
        }
        button.title = title
```

- [ ] **Step 6: Let the user choose it**

In `Sources/EyesUpApp/Dashboard/SettingsTab.swift`, add a section above "Safety":
```swift
                    Section("Menu bar") {
                        Picker("Show", selection: Binding(
                            get: { settings.menuBarReadout },
                            set: { readout in environment.settings.update { $0.menuBarReadout = readout } }
                        )) {
                            ForEach(MenuBarReadout.allCases, id: \.self) { readout in
                                Text(readout.title).tag(readout)
                            }
                        }
                        Text("Stats in the menu bar refresh every 2 seconds. With \"Icon only\" or \"Icon and time left\", nothing is measured at all.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
```

In `Sources/EyesUpApp/EyesUpGuardianApp.swift`, apply it at launch and on every settings change — add after the status item is built:
```swift
        statusItem.applyReadout(environment.settings.settings.menuBarReadout, center: environment.metrics)
        environment.onSettingsChanged = { [weak statusItem] settings in
            statusItem?.applyReadout(settings.menuBarReadout, center: environment.metrics)
        }
```

In `Sources/EyesUpApp/AppEnvironment.swift`, add the hook and call it from the existing settings handler:
```swift
    /// Set by the app delegate: UI that must react to a settings change.
    var onSettingsChanged: ((AppSettings) -> Void)?
```
and inside `settings.onChange` in `start()`, after `SettingsApplier.apply(...)`:
```swift
            onSettingsChanged?(settings)
```

- [ ] **Step 7: Run the tests and look at the menu bar**

Run: `make test && make app && open build/EyesUpGuardian.app`
Expected: tests pass. In the dashboard's Settings, choose **Icon, time, CPU and power**; within two seconds the menu bar shows something like `2:00 · 12% · 38.4 W`. Switch back to **Icon and time left** and the extra numbers disappear.
Run: `make perf`
Expected: `PASS` — the perf run uses the saved setting, so run it once with the readout on **Icon and time left** (the default) and once with CPU and power on; both must pass.

- [ ] **Step 8: Commit**

```bash
git add Sources Tests
git commit -m "feat(app): add the optional CPU and power readout in the menu bar" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 11: Processes tab

**Files:**
- Create: `Sources/EyesUpApp/Dashboard/ProcessesTab.swift`
- Modify: `Sources/EyesUpApp/Dashboard/DashboardWindow.swift` (add the tab and its state)

**Interfaces:**
- Consumes: `StatsViewModel` (with `[.processes, .system]`), `ProcessControl`, `ProcessControlError`, `AwakeController.watchProcess(pid:policy:)`, `StatFormatting`.
- Produces: `struct ProcessesTab: View`, `@Observable final class ProcessesState { var filter: String; var sort: ProcessSort; var confirmingQuit: ProcessEntry?; var forceQuit: Bool; var message: String? }`, `enum ProcessSort { cpu, memory, name }`.

Mission Control style: monospaced, dense, dark. Row actions follow spec §7.3 — keep awake until it exits, copy PID, reveal in Finder, and Quit/Force Quit for your own processes only, with a confirmation.

- [ ] **Step 1: Write the tab**

`Sources/EyesUpApp/Dashboard/ProcessesTab.swift`:
```swift
import AppKit
import EyesUpCore
import SwiftUI

enum ProcessSort: String, CaseIterable, Identifiable {
    case cpu, memory, name

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memory"
        case .name: "Name"
        }
    }
}

@MainActor
@Observable
final class ProcessesState {
    var filter = ""
    var sort: ProcessSort = .cpu
    var confirmingQuit: ProcessEntry?
    var forceQuit = false
    var message: String?
}

/// The dense "Mission Control" table (spec §7.3).
struct ProcessesTab: View {
    let environment: AppEnvironment
    @Bindable var stats: StatsViewModel
    @Bindable var state: ProcessesState

    private var entries: [ProcessEntry] {
        let all = stats.snapshot.processes ?? []
        let filtered = state.filter.isEmpty
            ? all
            : all.filter { $0.name.localizedCaseInsensitiveContains(state.filter) || String($0.pid).contains(state.filter) }
        return switch state.sort {
        case .cpu: filtered.sorted { $0.cpuPercent > $1.cpuPercent }
        case .memory: filtered.sorted { $0.memoryBytes > $1.memoryBytes }
        case .name: filtered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            table
            if let message = state.message {
                Label(message, systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary).padding(8)
            }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.7))
        .font(.system(size: 11, design: .monospaced))
        .onAppear { stats.start() }
        .onDisappear { stats.stop() }
        .confirmationDialog(
            state.confirmingQuit.map { "\(state.forceQuit ? "Force quit" : "Quit") \($0.name) (PID \($0.pid))?" } ?? "",
            isPresented: Binding(get: { state.confirmingQuit != nil }, set: { if !$0 { state.confirmingQuit = nil } }),
            titleVisibility: .visible
        ) {
            Button(state.forceQuit ? "Force Quit" : "Quit", role: .destructive) { confirmQuit() }
            Button("Cancel", role: .cancel) { state.confirmingQuit = nil }
        } message: {
            Text(state.forceQuit
                 ? "The process is ended immediately and unsaved work is lost."
                 : "The process is asked to quit.")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Processes").font(.system(size: 13, weight: .semibold))
            Text(summary).foregroundStyle(.secondary)
            Spacer()
            Picker("Sort", selection: $state.sort) {
                ForEach(ProcessSort.allCases) { sort in Text(sort.title).tag(sort) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            TextField("Filter", text: $state.filter)
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)
        }
        .padding(10)
    }

    private var summary: String {
        let all = stats.snapshot.processes ?? []
        let threads = all.reduce(0) { $0 + $1.threads }
        let load = stats.snapshot.system?.loadAverage
        let loadText = load.map { String(format: "load %.2f %.2f %.2f", $0.0, $0.1, $0.2) } ?? ""
        return "\(all.count) shown · \(threads) threads · \(loadText)"
    }

    private var table: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                row(name: "NAME", pid: "PID", cpu: "CPU%", memory: "MEM", threads: "THR", user: "USER")
                    .foregroundStyle(.secondary)
                ForEach(entries) { entry in
                    row(name: entry.name, pid: String(entry.pid),
                        cpu: String(format: "%.1f", entry.cpuPercent),
                        memory: StatFormatting.bytes(entry.memoryBytes),
                        threads: String(entry.threads),
                        user: entry.isOwn ? "you" : "sys")
                    .contentShape(Rectangle())
                    .contextMenu { menu(for: entry) }
                }
            }
        }
    }

    private func row(name: String, pid: String, cpu: String, memory: String, threads: String, user: String) -> some View {
        HStack(spacing: 8) {
            Text(name).frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
            Text(pid).frame(width: 60, alignment: .trailing)
            Text(cpu).frame(width: 60, alignment: .trailing)
            Text(memory).frame(width: 80, alignment: .trailing)
            Text(threads).frame(width: 45, alignment: .trailing)
            Text(user).frame(width: 40, alignment: .trailing).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func menu(for entry: ProcessEntry) -> some View {
        Button("Keep awake until this exits") { watch(entry) }
        Button("Copy PID") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(String(entry.pid), forType: .string)
        }
        Button("Reveal in Finder") { reveal(entry) }
        if entry.isOwn {
            Divider()
            Button("Quit…") {
                state.forceQuit = false
                state.confirmingQuit = entry
            }
            Button("Force Quit…", role: .destructive) {
                state.forceQuit = true
                state.confirmingQuit = entry
            }
        }
    }

    private func watch(_ entry: ProcessEntry) {
        do {
            let hold = try environment.controller.watchProcess(pid: entry.pid, policy: environment.controller.currentPolicy)
            state.message = "Keeping your Mac awake until \(hold.label) ends."
        } catch let error as AwakeError {
            state.message = error.message
        } catch {
            state.message = error.localizedDescription
        }
    }

    private func reveal(_ entry: ProcessEntry) {
        guard let path = LibprocInspector().executablePath(of: entry.pid) else {
            state.message = "That process's location isn't readable."
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private func confirmQuit() {
        guard let entry = state.confirmingQuit else { return }
        state.confirmingQuit = nil
        let inspector = LibprocInspector()
        guard let identity = inspector.identity(of: entry.pid) else {
            state.message = ProcessControlError.gone.message
            return
        }
        do {
            try ProcessControl().quit(identity, force: state.forceQuit)
            state.message = "\(state.forceQuit ? "Force quit" : "Asked to quit"): \(entry.name)."
        } catch let error as ProcessControlError {
            state.message = error.message
        } catch {
            state.message = error.localizedDescription
        }
    }
}
```

**Note on the security guard:** `NSWorkspace.shared.activateFileViewerSelecting` is not a forbidden API (the guard bans `open`, `openApplication`, `launchApplication` and `openURLs`), and revealing a file in Finder is not launching an app. If a later guard change flags it, keep the guard and drop the feature rather than widening the rule.

- [ ] **Step 2: Add `executablePath(of:)` to the inspector**

In `Sources/EyesUpCore/Processes/ProcessInspecting.swift`, add to the protocol and to `LibprocInspector`:
```swift
    func executablePath(of pid: Int32) -> String?
```
```swift
    public func executablePath(of pid: Int32) -> String? {
        guard pid > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
```
Add the matching stub to `FakeInspector` in `Tests/EyesUpCoreTests/Support/TriggerFakes.swift`:
```swift
    func executablePath(of pid: Int32) -> String? { paths[pid] }
```
with a stored property `var paths: [Int32: String] = [:]`.

- [ ] **Step 3: Add the tab**

In `Sources/EyesUpApp/Dashboard/DashboardWindow.swift`:
1. Extend the enum: `case overview, triggers, processes, settings`.
2. Title: `case .processes: "Processes"`; symbol: `case .processes: "list.bullet.rectangle"`.
3. Add state to `DashboardState`:
```swift
    var processesStats: StatsViewModel?
    let processes = ProcessesState()
```
4. In the detail switch:
```swift
                case .processes:
                    if let stats = state.processesStats {
                        ProcessesTab(environment: environment, stats: stats, state: state.processes)
                    }
```
5. In `show()`, beside the overview model:
```swift
        if state.processesStats == nil {
            state.processesStats = StatsViewModel(center: environment.metrics, ids: [.processes, .system], interval: 2)
        }
```

- [ ] **Step 4: Build and exercise it**

Run: `make test && make app && open build/EyesUpGuardian.app`
Expected: tests pass; the Processes tab lists processes sorted by CPU, updating every 2 s. Check each item:

| Action | Expected |
|---|---|
| Type `claude` in Filter | Only matching rows remain |
| Switch sort to Memory | Order changes; the heaviest process is first |
| Right-click a row → Copy PID | Pasting gives that number |
| Right-click → Keep awake until this exits | A hold appears; `pmset -g assertions \| grep EyesUpGuardian` names that process |
| Right-click a **system** row | No Quit items are offered |
| Right-click your own `sleep 300` → Quit… → Quit | The process ends and the message names it |
| Run `sleep 5`, wait for it to end, then Quit it from a stale row | "That process has already ended." and nothing else is signalled |

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "feat(app): add the Processes tab with filtering, sorting and safe quit" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 12: Floating HUD

**Files:**
- Create: `Sources/EyesUpApp/HUD/HUDWindow.swift`
- Modify: `Sources/EyesUpCore/Store/AppSettings.swift` (HUD visibility and position)
- Modify: `Sources/EyesUpApp/Popover/PopoverView.swift` (a pin button), `Sources/EyesUpApp/MenuBar/StatusItemController.swift` (a menu item), `Sources/EyesUpApp/EyesUpGuardianApp.swift` (own it)
- Modify: `Tests/EyesUpCoreTests/SettingsTests.swift`

**Interfaces:**
- Produces:
  - `AppSettings.hudVisible: Bool`, `AppSettings.hudPosition: HUDPosition` (`struct HUDPosition: Codable, Equatable, Sendable { x: Double; y: Double }`), with `validated()` dropping non-finite coordinates
  - `@MainActor final class HUDWindowController { init(environment:); func show(); func hide(); func toggle(); var isVisible: Bool }`
  - `struct HUDView: View`

- [ ] **Step 1: Write the failing test**

Append inside `@Suite @MainActor struct SettingsTests`:
```swift
    @Test func hudDefaultsToHiddenAndRejectsAbsurdPositions() {
        #expect(!AppSettings().hudVisible)
        #expect(AppSettings().hudPosition == nil)
        #expect(AppSettings(hudPosition: HUDPosition(x: .nan, y: 10)).validated().hudPosition == nil)
        #expect(AppSettings(hudPosition: HUDPosition(x: 1e9, y: 1e9)).validated().hudPosition == nil)
        #expect(AppSettings(hudPosition: HUDPosition(x: 120, y: 340)).validated().hudPosition == HUDPosition(x: 120, y: 340))
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `make test`
Expected: FAIL to compile with `cannot find 'HUDPosition' in scope`.

- [ ] **Step 3: Add the settings**

In `Sources/EyesUpCore/Store/AppSettings.swift`:
```swift
/// Where the floating HUD sits, in screen coordinates.
public struct HUDPosition: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}
```
Add to `AppSettings`: the stored properties `public var hudVisible: Bool` and `public var hudPosition: HUDPosition?`, memberwise parameters `hudVisible: Bool = false, hudPosition: HUDPosition? = nil`, the assignments, the lenient decodes (`?? false` and `nil`), and in `validated()`:
```swift
        if let position = settings.hudPosition {
            let sane = position.x.isFinite && position.y.isFinite
                && abs(position.x) < 100_000 && abs(position.y) < 100_000
            settings.hudPosition = sane ? position : nil
        }
```

- [ ] **Step 4: Write the HUD**

`Sources/EyesUpApp/HUD/HUDWindow.swift`:
```swift
import AppKit
import EyesUpCore
import SwiftUI

/// The pinnable mini panel (spec §7.4): countdown plus a compact stat line, on every Space,
/// faded until the mouse is over it.
struct HUDView: View {
    let controller: AwakeController
    @Bindable var stats: StatsViewModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 10) {
                Image(systemName: controller.isAwake ? "eye.fill" : "eye")
                    .foregroundStyle(controller.isAwake ? .orange : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(countdown(now: context.date))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(statLine).font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(AmbientBackground(mood: controller.isAwake ? .awake : .idle))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .onAppear { stats.start() }
        .onDisappear { stats.stop() }
    }

    private func countdown(now: Date) -> String {
        guard controller.isAwake else { return "Idle" }
        guard let until = controller.awakeUntil else { return "No end time" }
        return TimeFormatting.countdown(until.timeIntervalSince(now))
    }

    private var statLine: String {
        let snapshot = stats.snapshot
        var parts = ["CPU " + StatFormatting.percent(snapshot.cpu?.total)]
        if let memory = snapshot.memory { parts.append("RAM " + StatFormatting.bytes(memory.usedBytes)) }
        if let power = snapshot.power { parts.append(StatFormatting.watts(power.watts)) }
        if let temperature = snapshot.temperature { parts.append(StatFormatting.celsius(temperature.celsius)) }
        return parts.joined(separator: " · ")
    }
}

/// A borderless panel that floats above other windows without stealing focus.
@MainActor
final class HUDWindowController {
    private let environment: AppEnvironment
    private var panel: NSPanel?
    private var stats: StatsViewModel?

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        if let panel {
            panel.orderFrontRegardless()
            return
        }
        let model = StatsViewModel(center: environment.metrics, ids: [.cpu, .memory, .power, .temperature], interval: 1)
        stats = model
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 230, height: 56),
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: HUDView(controller: environment.controller, stats: model))
        place(panel)
        panel.orderFrontRegardless()
        self.panel = panel
        environment.settings.update { $0.hudVisible = true }
    }

    func hide() {
        savePosition()
        stats?.stop()
        stats = nil
        panel?.orderOut(nil)
        panel = nil
        environment.settings.update { $0.hudVisible = false }
    }

    /// Remembers where it was dragged to, so it comes back in the same corner.
    func savePosition() {
        guard let panel else { return }
        let origin = panel.frame.origin
        environment.settings.update { $0.hudPosition = HUDPosition(x: Double(origin.x), y: Double(origin.y)) }
    }

    private func place(_ panel: NSPanel) {
        if let saved = environment.settings.settings.hudPosition,
           let screen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: saved.x, y: saved.y)) }) ?? NSScreen.main,
           screen.frame.contains(NSPoint(x: saved.x, y: saved.y)) {
            panel.setFrameOrigin(NSPoint(x: saved.x, y: saved.y))
        } else if let screen = NSScreen.main {
            // Default: top-right, below the menu bar.
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.maxX - panel.frame.width - 20, y: frame.maxY - panel.frame.height - 20))
        }
    }
}
```

- [ ] **Step 5: Wire the toggles**

In `Sources/EyesUpApp/Popover/PopoverView.swift`, add to the footer before the Dashboard button:
```swift
            Button(onHUDToggle.isPinned() ? "Unpin HUD" : "Pin HUD") { onHUDToggle.toggle() }
                .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
```
and add a small value type so the view doesn't hold the controller:
```swift
    /// Lets the popover pin the HUD without knowing about windows.
    struct HUDToggle {
        var isPinned: () -> Bool
        var toggle: () -> Void
    }

    let onHUDToggle: HUDToggle
```

In `Sources/EyesUpApp/MenuBar/StatusItemController.swift`, add `var onToggleHUD: (() -> Void)?` and a menu item next to "Open Dashboard…":
```swift
        menu.addItem(menuItem("Pin HUD", #selector(toggleHUD)))
```
```swift
    @objc private func toggleHUD() { onToggleHUD?() }
```

In `Sources/EyesUpApp/EyesUpGuardianApp.swift`:
```swift
    private var hud: HUDWindowController?
```
and in `applicationDidFinishLaunching`, after the dashboard is built:
```swift
        let hud = HUDWindowController(environment: environment)
        statusItem.onToggleHUD = { hud.toggle() }
        self.hud = hud
        if environment.settings.settings.hudVisible { hud.show() }
```
passing the toggle into the popover:
```swift
            onHUDToggle: PopoverView.HUDToggle(isPinned: { hud.isVisible }, toggle: { hud.toggle() }),
```
and saving its position on quit, in `applicationWillTerminate` before `environment?.shutdown()`:
```swift
        hud?.savePosition()
```

- [ ] **Step 6: Build and try it**

Run: `make test && make app && open build/EyesUpGuardian.app`
Expected: tests pass. Check:

| Action | Expected |
|---|---|
| Popover → **Pin HUD** | A small panel appears top-right with the countdown and `CPU … · RAM … · 38.4 W · 58°C` |
| Drag it to another corner, quit, relaunch | It reappears where you left it |
| Switch to another Space or full-screen app | It stays visible |
| Click it | It doesn't steal focus from your app |
| Popover → **Unpin HUD** | It disappears, and sampling stops (Activity Monitor back to ~0%) |

- [ ] **Step 7: Commit**

```bash
git add Sources Tests
git commit -m "feat(app): add the pinnable floating HUD" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 13: Performance, docs and spec sync

**Files:**
- Modify: `docs/manual-test-checklist.md`, `README.md`, `SECURITY.md`, `docs/superpowers/specs/2026-09-19-eyesupguardian-design.md`

- [ ] **Step 1: Measure the three states**

Run each and record the numbers:
1. `make perf` with the default readout (Icon and time left), dashboard closed, HUD hidden.
   Expected: **PASS**, idle CPU < 0.1%.
2. With the HUD pinned and the readout set to CPU and power, run `make perf` again.
   Expected: still **PASS**. The HUD samples at 1 s, which is a visible surface, so if this fails the sampler is doing work it shouldn't.
3. Dashboard open on Overview: read EyesUpGuardian's CPU in Activity Monitor for 30 s.
   Expected: **under 1.5%** (spec §3.6). Note the figure in the checklist.

If any of these fails, do not raise the limit — use superpowers:systematic-debugging to find what is sampling when it shouldn't.

- [ ] **Step 2: Extend the manual checklist**

Append to `docs/manual-test-checklist.md`:
```markdown

## Stats and dashboard (Plan 3)
- [ ] Popover shows four tiles (CPU, Memory, Power, Uptime) updating about once a second.
- [ ] Closing the popover stops the updates (Activity Monitor: CPU back to ~0%).
- [ ] Overview: countdown, three sparklines filling over ~10 s, twelve tiles with real values.
- [ ] Power and fan tiles show numbers on this Mac (Mac Studio). On hardware without them, they read "—".
- [ ] Other apps holding the Mac awake are listed, in the popover and in Overview.
- [ ] Processes: sorted by CPU, filter works, sort switches, right-click offers Copy PID / Reveal / Keep awake until this exits.
- [ ] Quit is offered only for your own processes, asks for confirmation, and reports the outcome.
- [ ] Quitting a process that already ended says so instead of signalling anything.
- [ ] Menu-bar readout options each show what they promise; "Icon only" and "Icon and time left" measure nothing.
- [ ] HUD pins, drags, survives a relaunch in the same place, floats over full-screen apps, and stops sampling when unpinned.
- [ ] `make perf` passes with the HUD pinned and the stat readout on.
- [ ] Dashboard open: CPU under 1.5% in Activity Monitor.
```

- [ ] **Step 3: Update the README**

In `README.md`, add after the "Automatic keep-awake" section:
```markdown
## What your Mac is doing

The dashboard's **Overview** shows CPU (with performance and efficiency core averages), memory and pressure, power draw in watts, temperature, fan speed, GPU use, disk, network, uptime, load and thermal state — plus **which other apps are keeping your Mac awake**, which is usually the answer to "why won't it sleep?".

**Processes** lists what's running, sorted by CPU or memory, with a filter. Right-click any row to keep your Mac awake until that process exits, copy its PID, reveal it in Finder, or quit it (your own processes only, with a confirmation).

You can also put live stats in the menu bar next to the timer, and pin a small floating **HUD** that stays visible over other apps.

Everything is measured only while you're looking at it: close the dashboard and the popover, and the app goes back to measuring nothing.

**What needs no admin rights, and what isn't available:** power draw, fan speed and temperature come from the Mac's own sensors and work without a password. The per-chip power split (CPU vs GPU vs Neural Engine) is *not* included, because reading it needs a private interface this app deliberately avoids; the total is shown instead. Any reading your Mac doesn't provide shows as "—" rather than a made-up number.
```

- [ ] **Step 4: Note the new interfaces in SECURITY.md**

In `SECURITY.md`, add these rows to the "What it does touch" table:
```markdown
| AppleSMC user client (`IOConnectCallStructMethod`) | Power draw, fan speed and temperature. Read-only: the app only ever reads keys, never writes them. |
| `IOAccelerator` registry statistics | GPU utilization. |
| `host_processor_info`, `host_statistics64` | CPU and memory. |
| `proc_pid_rusage`, `proc_pidinfo` | The process table's CPU and memory columns. |
| `kill(2)` | Quit / Force Quit, for your own processes only, after re-checking the process identity. |
```

- [ ] **Step 5: Sync the spec**

In `docs/superpowers/specs/2026-09-19-eyesupguardian-design.md`:
1. In §6.2's undocumented-interfaces table, replace the IOReport row
```
| CPU / GPU / ANE watts, cluster frequencies | IOReport "Energy Model" and "CPU Stats" channels (`libIOReport.dylib`, loaded with `dlopen`/`dlsym` so a missing symbol means `.unavailable`, not a launch failure) |
```
with
```
| CPU / GPU / ANE watts, cluster frequencies | **Not implemented (Plan 3 decision).** It needs IOReport via `dlopen`, which §9.1's guard forbids. Total system power from the SMC covers the user-visible need. |
```
2. Replace the temperature row's source with:
```
| Temperatures | AppleSMC user client, a curated key list probed once (enumerating all 3,364 keys costs 638 ms). The hottest readable sensor is shown. |
```
3. In §6.1's visibility table, add a row after the dashboard row:
```
| Floating HUD | Its 4 stats at 1 s, stopping the moment it is unpinned |
```

- [ ] **Step 6: Final verification**

Run: `make test && make test-integration && make perf`
Expected: every suite green and `PASS`.
Then work through the new checklist section.

- [ ] **Step 7: Commit**

```bash
git add docs README.md SECURITY.md
git commit -m "docs: document the stats dashboard, processes, readout and HUD" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```
