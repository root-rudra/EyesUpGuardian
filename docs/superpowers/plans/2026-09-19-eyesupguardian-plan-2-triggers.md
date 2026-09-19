# EyesUpGuardian Plan 2: Triggers, Automation Link and Safety Guards

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Mac stay awake by itself — while chosen apps or command-line processes run, on a schedule, while the Mac is busy (CPU, network, disk), while a display is connected, or on AC power — plus an opt-in `eyesup://` automation link and the safety guards (thermal auto-release, a maximum-hold cap, pause-all).

**Architecture:**
- Each condition is a `ConditionMonitor` that reports true/false changes. `TriggerEngine` turns those edges into trigger-owned holds on the existing `AwakeController`, with per-trigger grace periods. Every system source (workspace, displays, power, thermal, process list, counters) sits behind a protocol, so all engine and monitor logic is testable with fakes.
- The safety cap is expressed as `Hold.expiry(safetyCap:)`, so the existing `DeadlineMonitor` enforces it with no new timer machinery.
- The UI gains a dashboard window whose sidebar has two tabs in this plan: **Triggers** and **Settings**. Plan 3 adds Overview and Processes; Plan 4 extends Settings.

**Tech Stack:** Swift 6.2, SwiftUI + AppKit (macOS 26), Foundation, CoreGraphics, IOKit (`IOKit.ps`, IOBlockStorageDriver), libproc, `sysctl` (`NET_RT_IFLIST2`), Swift Testing. No third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-09-19-eyesupguardian-design.md` (this plan implements §4.5, §5, §5.1, and the Triggers/Settings parts of §7.3)

**Builds on:** branch `plan-1-core-menu-bar` (Plan 1 complete: holds, engine, deadlines, store, menu bar, popover, notifications).

## Global Constraints

Everything in Plan 1's Global Constraints still holds. Repeated here because they bite in this plan:

- `// swift-tools-version: 6.2`, `platforms: [.macOS(.v26)]`, Swift 6 strict concurrency, **zero third-party dependencies** (`Package.swift` must never contain `.package(`).
- App code never executes commands, never touches the network, never escalates privileges. `SecurityGuardTests` fails the build otherwise.
- `EyesUpCore` must not import SwiftUI or AppKit. Foundation, Darwin, Dispatch, Observation, IOKit and CoreGraphics are allowed; **NSWorkspace is AppKit, so it stays in `EyesUpApp` behind the `WorkspaceEvents` protocol.**
- **Never use SwiftUI `@State`.** With the Command Line Tools only, the macOS 27 SDK makes it a macro whose plugin ships with Xcode. Use an `@Observable` class owned by the caller and `@Bindable` in the view (as `PopoverFormState` does).
- **Run tests with `make test` / `make test-integration`**, never bare `swift test` (the Makefile loads the Swift Testing macro plugin explicitly).
- Storage stays in `~/Library/Application Support/EyesUpGuardian/`, JSON, atomic writes, each file with a `schemaVersion`, bad files moved aside (`JSONFileStore`).
- Idle budget (spec §3): < 0.1% CPU over 60 s and ≤ 30 MB footprint, enforced by `make perf`. **Polling monitors run only while their trigger is enabled**: process-running every 10 s, activity every 15 s.
- Assertion names start with `EyesUpGuardian` and are at most 128 characters.
- End every commit message with `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.

## Decisions this plan records (spec clarifications)

1. **Process-running triggers poll only.** Spec §5 says the trigger switches to kqueue exit watching once it matches. Polling every 10 s already bounds the release delay at 10 s, before any grace period, so this plan keeps polling and drops the kqueue switch. Task 16 updates the spec.
2. **`stop` from the automation link only ends automation's own holds.** The spec says the link accepts start/stop/extend but does not say whose sessions `stop` ends. Least power wins: a link can never cancel what you started by hand.
3. **The dashboard window arrives here, with Triggers and Settings tabs**, because triggers need somewhere to live. Spec §7.3's other three tabs stay in Plans 3–4.
4. **The safety cap applies to every hold, including trigger holds** (spec §4.5 says "no hold"). A capped trigger hold does not come back until its condition goes false and true again.
5. **Suggestions use the built-in app list only.** Spec §5 also suggests apps "the user has held for before", which needs the session history that arrives in Plan 4. Until then, the six known apps are the whole list.
6. **Process names are matched case-insensitively** against the names this user can see. macOS hides other users' and root's process names from `libproc`, so `sudo`-run processes can't be matched; that is a documented limit, not a bug.

## Review Focus

1. **A flapping condition** (an app that relaunches, CPU hovering at the threshold, a display waking) must not thrash assertions or leave orphan holds. Tests: Task 3 `gateIgnoresBriefSpikes`/`gateHoldsThroughBriefDips`; Task 5 `repeatedReportsDoNotDuplicateHolds` and `conditionReturningDuringGraceKeepsOneHold`.
2. **Pause across sleep.** "Pause for 1h" while the Mac sleeps past the resume time must resume on wake and re-apply conditions that are still true. Tests: Task 5 `refreshResumesAPauseThatExpiredWhileAsleep`, `resumeReappliesStillTrueConditions`.
3. **A hostile or malformed `eyesup://` link** (unknown command, duplicate or unexpected parameters, `999h`, whitespace, non-ASCII digits, `display=maybe`) must be rejected, and `stop` must never touch hand-made holds. Tests: Task 10 `rejectsMalformedLinks`, `stopOnlyEndsAutomationHolds`.
4. **A corrupt, invalid or oversized `triggers.json`** must give a clean start with a notice and no crash — including a trigger whose grace or threshold is absurd. Tests: Task 1 `sanitizedRejectsOutOfRangeValues`; Task 5 `loadDropsInvalidTriggersWithNotice`, `loadReportsCorruptStore`.
5. **Schedules around midnight, DST and timezone changes.** A window that crosses midnight must end on time, a DST jump must not strand it on or off, and changing timezone must re-evaluate. Tests: Task 2 `crossesMidnight`, `springForwardHasABoundary`, `nextBoundaryFollowsTheCalendar`; Task 6 `scheduleMonitorReevaluatesOnDemand`.

---

## File map

```
Sources/EyesUpCore/
├── Holds/Hold.swift                          MODIFY (Task 4): expiry(safetyCap:), awakeUntil(_:safetyCap:)
├── Engine/DeadlineMonitor.swift              MODIFY (Task 4): safetyCap property
├── AwakeController.swift                     MODIFY (Tasks 4, 10): trigger holds, cap, onSafetyRelease, apply(_:)
├── Triggers/Trigger.swift                    Task 1: Trigger, TriggerCondition, Schedule, ActivityThreshold, DisplayMatch
├── Triggers/TriggerValidator.swift           Task 1
├── Triggers/TriggerSuggestions.swift         Task 1
├── Triggers/ScheduleEvaluation.swift         Task 2
├── Triggers/ActivityGate.swift               Task 3: ActivityGate, RateMeter, CPUMeter
├── Triggers/ConditionMonitor.swift           Task 5: protocols
├── Triggers/TriggerEngine.swift              Task 5
├── Triggers/SystemSources.swift              Task 6: WorkspaceEvents, DisplayInventory, PowerSourceInfo,
│                                                      ProcessLister, SystemCounters, ThermalMonitoring, ThermalLevel
├── Triggers/EventMonitors.swift              Task 6: AppRunning, DisplayConnected, PowerSource, Schedule monitors
├── Triggers/PollingMonitors.swift            Task 7: ProcessRunningMonitor, ActivityMonitor
├── System/LiveSystemSources.swift            Task 8: live counters, lister, displays, power, thermal + C callbacks
├── System/LiveConditionMonitorFactory.swift  Task 8
├── Store/AppSettings.swift                   Task 9: AppSettings, TriggerPause, SettingsController
├── Automation/AutomationCommand.swift        Task 10: command + parser
└── Safety/SafetyGuard.swift                  Task 11: thermal release + SettingsApplier

Sources/EyesUpApp/
├── System/LiveWorkspaceEvents.swift          Task 12 (NSWorkspace)
├── AppEnvironment.swift                      MODIFY (Task 12): engine, settings, safety guard, timezone refresh
├── Notifications/HeadsUpNotifier.swift       MODIFY (Task 12): postInfo(_:id:)
├── EyesUpGuardianApp.swift                   MODIFY (Tasks 12, 13, 15): wiring, dashboard, URL handling
├── MenuBar/StatusItemController.swift        MODIFY (Task 13): "Open Dashboard" item + onOpenDashboard
├── Popover/PopoverView.swift                 MODIFY (Task 13): "Dashboard ↗" footer button
├── Dashboard/DashboardWindow.swift           Task 13: window controller + DashboardState + DashboardView
├── Dashboard/TriggersTab.swift               Task 14
├── Dashboard/TriggerDraft.swift              Task 14
├── Dashboard/TriggerEditorSheet.swift        Task 14
└── Dashboard/SettingsTab.swift               Task 15
└── Resources/Info.plist                      MODIFY (Task 15): CFBundleURLTypes

Tests/EyesUpCoreTests/
├── Support/TriggerFakes.swift                Task 1 (grows in Tasks 5, 6, 7, 11)
├── TriggerModelTests.swift                   Task 1
├── ScheduleTests.swift                       Task 2
├── ActivityGateTests.swift                   Task 3
├── AwakeControllerTests.swift                MODIFY (Tasks 4, 10)
├── TriggerEngineTests.swift                  Task 5
├── EventMonitorTests.swift                   Task 6
├── PollingMonitorTests.swift                 Task 7
├── LiveSystemSourcesTests.swift              Task 8
├── SettingsTests.swift                       Task 9
├── AutomationTests.swift                     Task 10
└── SafetyGuardTests.swift                    Task 11

Tests/EyesUpAppTests/TriggerDraftTests.swift  Task 14
docs/manual-test-checklist.md                 MODIFY (Task 16)
README.md                                     MODIFY (Task 16)
```

---

### Task 1: Trigger model, validation and suggestions

**Files:**
- Create: `Sources/EyesUpCore/Triggers/Trigger.swift`, `Sources/EyesUpCore/Triggers/TriggerValidator.swift`, `Sources/EyesUpCore/Triggers/TriggerSuggestions.swift`
- Create: `Tests/EyesUpCoreTests/Support/TriggerFakes.swift`, `Tests/EyesUpCoreTests/TriggerModelTests.swift`

**Interfaces:**
- Consumes: `SleepPolicy`, `HoldRestorer.knownPolicy` (Plan 1).
- Produces:
  - `struct Schedule { weekdays: Set<Int>; startMinute: Int; endMinute: Int }`
  - `struct ActivityThreshold { value: Double; sustain: TimeInterval; release: TimeInterval }`
  - `struct DisplayMatch { vendor, model, serial: UInt32; name: String; func matches(_:) -> Bool }`
  - `enum TriggerCondition { appRunning(bundleIDs:), processRunning(names:), schedule(_), cpuBusy(_), networkBusy(_), diskBusy(_), displayConnected(_), onACPower }`
  - `struct Trigger { id, name, condition, policy, grace, notifyOnChange, isEnabled; var summary: String }`
  - `enum TriggerValidator { static func sanitized(_:) -> Trigger?; maxNameLength = 80; maxIdentifiers = 32; maxIdentifierLength = 255; maxGrace = 86400; maxSustain = 86400 }`
  - `struct TriggerSuggestion { bundleID, displayName }`, `enum TriggerSuggestions { knownApps, suggestions(running:existing:) }`
  - Test helper `makeTrigger(...)`.

- [ ] **Step 1: Write the failing tests**

`Tests/EyesUpCoreTests/Support/TriggerFakes.swift`:
```swift
import Foundation
@testable import EyesUpCore

func makeTrigger(
    id: UUID = UUID(),
    name: String = "Test trigger",
    condition: TriggerCondition = .onACPower,
    policy: SleepPolicy = .system,
    grace: TimeInterval = 0,
    notifyOnChange: Bool = false,
    isEnabled: Bool = true
) -> Trigger {
    Trigger(id: id, name: name, condition: condition, policy: policy, grace: grace,
            notifyOnChange: notifyOnChange, isEnabled: isEnabled)
}
```

`Tests/EyesUpCoreTests/TriggerModelTests.swift`:
```swift
import Foundation
import Testing
@testable import EyesUpCore

@Suite struct TriggerModelTests {
    @Test func triggersRoundTripThroughJSON() throws {
        let triggers = [
            makeTrigger(condition: .appRunning(bundleIDs: ["com.anthropic.claudefordesktop"])),
            makeTrigger(condition: .processRunning(names: ["node"]), grace: 300),
            makeTrigger(condition: .schedule(Schedule(weekdays: [2, 3], startMinute: 540, endMinute: 1080))),
            makeTrigger(condition: .cpuBusy(ActivityThreshold(value: 40))),
            makeTrigger(condition: .networkBusy(ActivityThreshold(value: 1_000_000))),
            makeTrigger(condition: .diskBusy(ActivityThreshold(value: 20_000_000))),
            makeTrigger(condition: .displayConnected(DisplayMatch(vendor: 7789, model: 30734, serial: 47852, name: "LG"))),
            makeTrigger(condition: .onACPower, notifyOnChange: true, isEnabled: false),
        ]
        let data = try JSONEncoder().encode(triggers)
        #expect(try JSONDecoder().decode([Trigger].self, from: data) == triggers)
    }

    @Test func sanitizedTrimsAndKeepsValidTriggers() throws {
        let trigger = makeTrigger(name: "  Claude running  ", condition: .appRunning(bundleIDs: [" com.anthropic.claudefordesktop ", "com.anthropic.claudefordesktop", ""]))
        let clean = try #require(TriggerValidator.sanitized(trigger))
        #expect(clean.name == "Claude running")
        #expect(clean.condition == .appRunning(bundleIDs: ["com.anthropic.claudefordesktop"]))
    }

    @Test func sanitizedRejectsOutOfRangeValues() {
        #expect(TriggerValidator.sanitized(makeTrigger(name: "   ")) == nil)
        #expect(TriggerValidator.sanitized(makeTrigger(grace: -1)) == nil)
        #expect(TriggerValidator.sanitized(makeTrigger(grace: 86_401)) == nil)
        #expect(TriggerValidator.sanitized(makeTrigger(policy: SleepPolicy(rawValue: 1 << 9))) == nil)
        #expect(TriggerValidator.sanitized(makeTrigger(condition: .appRunning(bundleIDs: []))) == nil)
        #expect(TriggerValidator.sanitized(makeTrigger(condition: .processRunning(names: [String(repeating: "x", count: 300)]))) == nil)
        #expect(TriggerValidator.sanitized(makeTrigger(condition: .cpuBusy(ActivityThreshold(value: 0)))) == nil)
        #expect(TriggerValidator.sanitized(makeTrigger(condition: .cpuBusy(ActivityThreshold(value: 101)))) == nil)
        #expect(TriggerValidator.sanitized(makeTrigger(condition: .cpuBusy(ActivityThreshold(value: 50, sustain: 90_000)))) == nil)
        #expect(TriggerValidator.sanitized(makeTrigger(condition: .networkBusy(ActivityThreshold(value: 10)))) == nil)
        #expect(TriggerValidator.sanitized(makeTrigger(condition: .networkBusy(ActivityThreshold(value: .infinity)))) == nil)
        #expect(TriggerValidator.sanitized(makeTrigger(condition: .schedule(Schedule(weekdays: [], startMinute: 0, endMinute: 60)))) == nil)
        #expect(TriggerValidator.sanitized(makeTrigger(condition: .schedule(Schedule(weekdays: [9], startMinute: 0, endMinute: 60)))) == nil)
        #expect(TriggerValidator.sanitized(makeTrigger(condition: .schedule(Schedule(weekdays: [2], startMinute: 600, endMinute: 600)))) == nil)
        #expect(TriggerValidator.sanitized(makeTrigger(condition: .schedule(Schedule(weekdays: [2], startMinute: -1, endMinute: 60)))) == nil)
        #expect(TriggerValidator.sanitized(makeTrigger(condition: .displayConnected(DisplayMatch(vendor: 0, model: 0, serial: 0, name: "?")))) == nil)
    }

    @Test func sanitizedCapsIdentifierCountAndMasksPolicy() throws {
        let many = (0..<40).map { "com.example.app\($0)" }
        let clean = try #require(TriggerValidator.sanitized(makeTrigger(
            condition: .appRunning(bundleIDs: many),
            policy: SleepPolicy(rawValue: SleepPolicy.system.rawValue | 1 << 9)
        )))
        guard case .appRunning(let ids) = clean.condition else { Issue.record("wrong condition"); return }
        #expect(ids.count == TriggerValidator.maxIdentifiers)
        #expect(clean.policy == .system)
    }

    @Test func summaryDescribesTheCondition() {
        #expect(makeTrigger(condition: .onACPower).summary == "While on AC power")
        #expect(makeTrigger(condition: .processRunning(names: ["node", "claude"])).summary == "While node or claude is running")
        #expect(makeTrigger(condition: .cpuBusy(ActivityThreshold(value: 40, sustain: 120))).summary == "While CPU is above 40% for 2m")
    }

    @Test func suggestsRunningKnownAppsThatHaveNoTriggerYet() {
        let running: Set<String> = ["com.anthropic.claudefordesktop", "com.apple.Terminal", "com.example.other"]
        let existing = [makeTrigger(condition: .appRunning(bundleIDs: ["com.apple.Terminal"]))]
        let suggestions = TriggerSuggestions.suggestions(running: running, existing: existing)
        #expect(suggestions.map(\.bundleID) == ["com.anthropic.claudefordesktop"])
        #expect(suggestions.first?.displayName == "Claude")
        #expect(TriggerSuggestions.suggestions(running: [], existing: []).isEmpty)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test`
Expected: FAIL to compile with `cannot find 'Trigger' in scope`.

- [ ] **Step 3: Write the model**

`Sources/EyesUpCore/Triggers/Trigger.swift`:
```swift
import Foundation

/// A day-of-week plus time-of-day window. Minutes are minutes since local midnight.
public struct Schedule: Codable, Hashable, Sendable {
    /// Calendar weekdays (1 = Sunday … 7 = Saturday) on which the window *starts*.
    public var weekdays: Set<Int>
    public var startMinute: Int
    public var endMinute: Int

    public init(weekdays: Set<Int>, startMinute: Int, endMinute: Int) {
        self.weekdays = weekdays
        self.startMinute = startMinute
        self.endMinute = endMinute
    }
}

/// A threshold plus the "busy for" and "quiet for" times that stop it flickering.
public struct ActivityThreshold: Codable, Hashable, Sendable {
    /// CPU uses percent (1…100); network and disk use bytes per second.
    public var value: Double
    public var sustain: TimeInterval
    public var release: TimeInterval

    public init(value: Double, sustain: TimeInterval = 120, release: TimeInterval = 300) {
        self.value = value
        self.sustain = sustain
        self.release = release
    }
}

/// Identifies a display across unplugs, using CoreGraphics' vendor/model/serial numbers.
public struct DisplayMatch: Codable, Hashable, Sendable {
    public var vendor: UInt32
    public var model: UInt32
    public var serial: UInt32
    public var name: String

    public init(vendor: UInt32, model: UInt32, serial: UInt32, name: String) {
        self.vendor = vendor
        self.model = model
        self.serial = serial
        self.name = name
    }

    public func matches(_ other: DisplayMatch) -> Bool {
        vendor == other.vendor && model == other.model && serial == other.serial
    }
}

public enum TriggerCondition: Codable, Hashable, Sendable {
    case appRunning(bundleIDs: [String])
    case processRunning(names: [String])
    case schedule(Schedule)
    case cpuBusy(ActivityThreshold)
    case networkBusy(ActivityThreshold)
    case diskBusy(ActivityThreshold)
    case displayConnected(DisplayMatch)
    case onACPower
}

/// A saved rule: while its condition holds, the Mac stays awake.
public struct Trigger: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var condition: TriggerCondition
    public var policy: SleepPolicy
    /// Stay awake this long after the condition ends.
    public var grace: TimeInterval
    public var notifyOnChange: Bool
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        condition: TriggerCondition,
        policy: SleepPolicy = .system,
        grace: TimeInterval = 0,
        notifyOnChange: Bool = false,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.condition = condition
        self.policy = policy
        self.grace = grace
        self.notifyOnChange = notifyOnChange
        self.isEnabled = isEnabled
    }

    public var summary: String {
        switch condition {
        case .appRunning(let ids): "While \(Self.list(ids)) is open"
        case .processRunning(let names): "While \(Self.list(names)) is running"
        case .schedule(let schedule): "On \(schedule.weekdaySummary) from \(Schedule.time(schedule.startMinute)) to \(Schedule.time(schedule.endMinute))"
        case .cpuBusy(let threshold): "While CPU is above \(Int(threshold.value))% for \(TimeFormatting.duration(threshold.sustain))"
        case .networkBusy(let threshold): "While network traffic is above \(Self.rate(threshold.value)) for \(TimeFormatting.duration(threshold.sustain))"
        case .diskBusy(let threshold): "While disk writes are above \(Self.rate(threshold.value)) for \(TimeFormatting.duration(threshold.sustain))"
        case .displayConnected(let display): "While \(display.name) is connected"
        case .onACPower: "While on AC power"
        }
    }

    private static func list(_ values: [String]) -> String {
        guard values.count > 1 else { return values.first ?? "" }
        return values.dropLast().joined(separator: ", ") + " or " + (values.last ?? "")
    }

    private static func rate(_ bytesPerSecond: Double) -> String {
        let megabytes = bytesPerSecond / 1_000_000
        return megabytes >= 1 ? String(format: "%.0f MB/s", megabytes) : String(format: "%.0f KB/s", bytesPerSecond / 1000)
    }
}

extension Schedule {
    public static func time(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    public var weekdaySummary: String {
        let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let selected = weekdays.sorted().compactMap { (1...7).contains($0) ? names[$0 - 1] : nil }
        if Set(weekdays) == Set(2...6) { return "weekdays" }
        if Set(weekdays) == Set([1, 7]) { return "weekends" }
        if weekdays.count == 7 { return "every day" }
        return selected.joined(separator: ", ")
    }
}
```

`Sources/EyesUpCore/Triggers/TriggerValidator.swift`:
```swift
import Foundation

/// Saved triggers are untrusted input (spec §9.5): everything is range-checked before it runs.
public enum TriggerValidator {
    public static let maxNameLength = 80
    public static let maxIdentifierLength = 255
    public static let maxIdentifiers = 32
    public static let maxGrace: TimeInterval = 24 * 3600
    public static let maxSustain: TimeInterval = 24 * 3600
    /// Below this, a network or disk threshold would fire on background noise.
    public static let minByteRate: Double = 1024

    /// The trigger with text trimmed and unknown policy bits removed, or nil if it can't be made valid.
    public static func sanitized(_ trigger: Trigger) -> Trigger? {
        var clean = trigger
        clean.name = String(clean.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxNameLength))
        clean.policy = clean.policy.intersection(HoldRestorer.knownPolicy)
        guard !clean.name.isEmpty, !clean.policy.isEmpty, clean.grace.isFinite, (0...maxGrace).contains(clean.grace) else { return nil }

        switch clean.condition {
        case .appRunning(let ids):
            guard let cleaned = identifiers(ids) else { return nil }
            clean.condition = .appRunning(bundleIDs: cleaned)
        case .processRunning(let names):
            guard let cleaned = identifiers(names) else { return nil }
            clean.condition = .processRunning(names: cleaned)
        case .schedule(let schedule):
            guard !schedule.weekdays.isEmpty, schedule.weekdays.allSatisfy({ (1...7).contains($0) }),
                  (0..<1440).contains(schedule.startMinute), (0..<1440).contains(schedule.endMinute),
                  schedule.startMinute != schedule.endMinute else { return nil }
        case .cpuBusy(let threshold):
            guard threshold.value >= 1, threshold.value <= 100, timings(threshold) else { return nil }
        case .networkBusy(let threshold), .diskBusy(let threshold):
            guard threshold.value.isFinite, threshold.value >= minByteRate, timings(threshold) else { return nil }
        case .displayConnected(let display):
            guard display.vendor != 0 || display.model != 0 || display.serial != 0 else { return nil }
        case .onACPower:
            break
        }
        return clean
    }

    private static func timings(_ threshold: ActivityThreshold) -> Bool {
        threshold.sustain.isFinite && threshold.release.isFinite
            && (0...maxSustain).contains(threshold.sustain) && (0...maxSustain).contains(threshold.release)
    }

    /// Trimmed, de-duplicated, length-limited identifiers; nil when nothing usable is left.
    private static func identifiers(_ values: [String]) -> [String]? {
        var unique: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.count <= maxIdentifierLength,
                  !trimmed.contains(where: \.isNewline), !unique.contains(trimmed) else { continue }
            unique.append(trimmed)
        }
        unique = Array(unique.prefix(maxIdentifiers))
        return unique.isEmpty ? nil : unique
    }
}
```

`Sources/EyesUpCore/Triggers/TriggerSuggestions.swift`:
```swift
import Foundation

public struct TriggerSuggestion: Identifiable, Hashable, Sendable {
    public var id: String { bundleID }
    public let bundleID: String
    public let displayName: String
}

/// One-click "Keep awake while X runs?" offers for apps the user already has open (spec §5).
public enum TriggerSuggestions {
    public static let knownApps: [(bundleID: String, name: String)] = [
        ("com.anthropic.claudefordesktop", "Claude"),
        ("com.apple.Terminal", "Terminal"),
        ("com.googlecode.iterm2", "iTerm"),
        ("com.apple.dt.Xcode", "Xcode"),
        ("com.microsoft.VSCode", "Visual Studio Code"),
        ("com.docker.docker", "Docker"),
    ]

    public static func suggestions(running: Set<String>, existing: [Trigger]) -> [TriggerSuggestion] {
        var covered: Set<String> = []
        for trigger in existing {
            if case .appRunning(let ids) = trigger.condition { covered.formUnion(ids) }
        }
        return knownApps
            .filter { running.contains($0.bundleID) && !covered.contains($0.bundleID) }
            .map { TriggerSuggestion(bundleID: $0.bundleID, displayName: $0.name) }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `make test`
Expected: every `TriggerModelTests` case passes, and Plan 1's suites stay green.

- [ ] **Step 5: Commit**

```bash
git add Sources/EyesUpCore/Triggers Tests/EyesUpCoreTests
git commit -m "feat(core): add trigger model, validation and app suggestions" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: Schedule evaluation (midnight, DST, timezones)

**Files:**
- Create: `Sources/EyesUpCore/Triggers/ScheduleEvaluation.swift`, `Tests/EyesUpCoreTests/ScheduleTests.swift`

**Interfaces:**
- Consumes: `Schedule` (Task 1).
- Produces: `Schedule.isActive(at:calendar:) -> Bool`, `Schedule.nextBoundary(after:calendar:) -> Date?`.

- [ ] **Step 1: Write the failing tests**

`Tests/EyesUpCoreTests/ScheduleTests.swift`:
```swift
import Foundation
import Testing
@testable import EyesUpCore

@Suite struct ScheduleTests {
    private func calendar(_ identifier: String = "America/New_York") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// Weekdays 09:00–18:00. 2026-09-21 is a Monday.
    private let workdays = Schedule(weekdays: [2, 3, 4, 5, 6], startMinute: 9 * 60, endMinute: 18 * 60)

    @Test func activeInsideTheWindowOnSelectedDays() {
        let calendar = calendar()
        #expect(workdays.isActive(at: date(2026, 9, 21, 10, 0, in: calendar), calendar: calendar))
        #expect(!workdays.isActive(at: date(2026, 9, 21, 8, 59, in: calendar), calendar: calendar))
        #expect(workdays.isActive(at: date(2026, 9, 21, 9, 0, in: calendar), calendar: calendar))
        #expect(!workdays.isActive(at: date(2026, 9, 21, 18, 0, in: calendar), calendar: calendar))
        #expect(!workdays.isActive(at: date(2026, 9, 20, 10, 0, in: calendar), calendar: calendar)) // Sunday
    }

    @Test func crossesMidnight() {
        let calendar = calendar()
        // Friday 22:00 until 02:00 the next morning.
        let nightShift = Schedule(weekdays: [6], startMinute: 22 * 60, endMinute: 2 * 60)
        #expect(nightShift.isActive(at: date(2026, 9, 25, 23, 30, in: calendar), calendar: calendar)) // Fri night
        #expect(nightShift.isActive(at: date(2026, 9, 26, 1, 30, in: calendar), calendar: calendar))  // Sat 01:30
        #expect(!nightShift.isActive(at: date(2026, 9, 26, 2, 0, in: calendar), calendar: calendar))  // Sat 02:00
        #expect(!nightShift.isActive(at: date(2026, 9, 26, 23, 0, in: calendar), calendar: calendar)) // Sat night
        #expect(!nightShift.isActive(at: date(2026, 9, 25, 21, 0, in: calendar), calendar: calendar)) // Fri 21:00
    }

    @Test func nextBoundaryFollowsTheCalendar() {
        let calendar = calendar()
        let monday8 = date(2026, 9, 21, 8, 0, in: calendar)
        #expect(workdays.nextBoundary(after: monday8, calendar: calendar) == date(2026, 9, 21, 9, 0, in: calendar))
        let monday10 = date(2026, 9, 21, 10, 0, in: calendar)
        #expect(workdays.nextBoundary(after: monday10, calendar: calendar) == date(2026, 9, 21, 18, 0, in: calendar))
    }

    @Test func springForwardHasABoundary() {
        // 2026-03-08: US clocks jump 02:00 → 03:00, so 02:30 does not exist that day.
        let calendar = calendar()
        let nightly = Schedule(weekdays: [1, 2, 3, 4, 5, 6, 7], startMinute: 2 * 60 + 30, endMinute: 4 * 60)
        let before = date(2026, 3, 8, 1, 0, in: calendar)
        let boundary = try? #require(nightly.nextBoundary(after: before, calendar: calendar))
        #expect(boundary != nil)
        #expect((boundary ?? before) > before)
    }

    @Test func timeZoneChangesTheAnswer() {
        let newYork = calendar()
        let tokyo = calendar("Asia/Tokyo")
        let instant = date(2026, 9, 21, 10, 0, in: newYork) // 23:00 in Tokyo
        #expect(workdays.isActive(at: instant, calendar: newYork))
        #expect(!workdays.isActive(at: instant, calendar: tokyo))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test --filter ScheduleTests` (the Makefile passes extra words through; if it doesn't, run `make test` and read the ScheduleTests lines)
Expected: FAIL to compile with `value of type 'Schedule' has no member 'isActive'`.

- [ ] **Step 3: Implement schedule evaluation**

`Sources/EyesUpCore/Triggers/ScheduleEvaluation.swift`:
```swift
import Foundation

extension Schedule {
    /// True when `date` falls inside a window that started on one of the selected weekdays.
    public func isActive(at date: Date, calendar: Calendar) -> Bool {
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        let weekday = calendar.component(.weekday, from: date)

        if startMinute < endMinute {
            return weekdays.contains(weekday) && minute >= startMinute && minute < endMinute
        }
        // The window crosses midnight, so it belongs to the day it started on.
        if weekdays.contains(weekday) && minute >= startMinute { return true }
        let previousDay = weekday == 1 ? 7 : weekday - 1
        return weekdays.contains(previousDay) && minute < endMinute
    }

    /// The next moment `isActive` can change, or nil if it never does.
    /// Looks 8 days ahead so a once-a-week window always has a boundary.
    public func nextBoundary(after date: Date, calendar: Calendar) -> Date? {
        var candidates: [Date] = []
        for dayOffset in 0...8 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: date) else { continue }
            for minute in [startMinute, endMinute] {
                // On a DST spring-forward day the wall time may not exist; Calendar moves to the next valid time.
                guard let candidate = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day),
                      candidate > date else { continue }
                candidates.append(candidate)
            }
        }
        return candidates.min()
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `make test`
Expected: all `ScheduleTests` pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/EyesUpCore/Triggers/ScheduleEvaluation.swift Tests/EyesUpCoreTests/ScheduleTests.swift
git commit -m "feat(core): evaluate schedules across midnight, DST and timezones" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: Activity gate and rate meters

**Files:**
- Create: `Sources/EyesUpCore/Triggers/ActivityGate.swift`, `Tests/EyesUpCoreTests/ActivityGateTests.swift`

**Interfaces:**
- Consumes: `ActivityThreshold` (Task 1).
- Produces:
  - `struct ActivityGate { init(threshold:); mutating func update(value:at:) -> Bool; var isOn: Bool }`
  - `struct RateMeter { mutating func rate(for: UInt64, at: Date) -> Double? }`
  - `struct CPUMeter { mutating func percent(busy: UInt64, total: UInt64) -> Double? }`

- [ ] **Step 1: Write the failing tests**

`Tests/EyesUpCoreTests/ActivityGateTests.swift`:
```swift
import Foundation
import Testing
@testable import EyesUpCore

@Suite struct ActivityGateTests {
    private let threshold = ActivityThreshold(value: 40, sustain: 120, release: 300)

    @Test func turnsOnOnlyAfterSustainedActivity() {
        var gate = ActivityGate(threshold: threshold)
        #expect(!gate.update(value: 90, at: referenceDate))
        #expect(!gate.update(value: 90, at: referenceDate.addingTimeInterval(60)))
        #expect(gate.update(value: 90, at: referenceDate.addingTimeInterval(120)))
        #expect(gate.isOn)
    }

    @Test func gateIgnoresBriefSpikes() {
        var gate = ActivityGate(threshold: threshold)
        #expect(!gate.update(value: 95, at: referenceDate))
        #expect(!gate.update(value: 5, at: referenceDate.addingTimeInterval(15)))
        #expect(!gate.update(value: 95, at: referenceDate.addingTimeInterval(30)))
        #expect(!gate.update(value: 95, at: referenceDate.addingTimeInterval(100)))
    }

    @Test func gateHoldsThroughBriefDips() {
        var gate = ActivityGate(threshold: threshold)
        _ = gate.update(value: 90, at: referenceDate)
        _ = gate.update(value: 90, at: referenceDate.addingTimeInterval(120))
        #expect(gate.isOn)
        #expect(gate.update(value: 1, at: referenceDate.addingTimeInterval(180)))   // dip
        #expect(gate.update(value: 90, at: referenceDate.addingTimeInterval(240)))  // busy again
        #expect(gate.update(value: 1, at: referenceDate.addingTimeInterval(300)))
        #expect(!gate.update(value: 1, at: referenceDate.addingTimeInterval(601)))  // quiet long enough
    }

    @Test func zeroSustainTurnsOnAtOnce() {
        var gate = ActivityGate(threshold: ActivityThreshold(value: 10, sustain: 0, release: 0))
        #expect(gate.update(value: 50, at: referenceDate))
        #expect(!gate.update(value: 1, at: referenceDate.addingTimeInterval(1)))
    }

    @Test func rateMeterNeedsTwoSamplesAndIgnoresCounterResets() {
        var meter = RateMeter()
        #expect(meter.rate(for: 1000, at: referenceDate) == nil)
        #expect(meter.rate(for: 3000, at: referenceDate.addingTimeInterval(2)) == 1000)
        #expect(meter.rate(for: 10, at: referenceDate.addingTimeInterval(4)) == nil) // counter reset
        #expect(meter.rate(for: 20, at: referenceDate.addingTimeInterval(6)) == 5)
        #expect(meter.rate(for: 30, at: referenceDate.addingTimeInterval(6)) == nil) // no time passed
    }

    @Test func cpuMeterConvertsTicksToPercent() {
        var meter = CPUMeter()
        #expect(meter.percent(busy: 100, total: 1000) == nil)
        #expect(meter.percent(busy: 150, total: 1100) == 50)
        #expect(meter.percent(busy: 150, total: 1100) == nil) // no new ticks
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test`
Expected: FAIL to compile with `cannot find 'ActivityGate' in scope`.

- [ ] **Step 3: Implement the gate and meters**

`Sources/EyesUpCore/Triggers/ActivityGate.swift`:
```swift
import Foundation

/// Turns a noisy measurement into a stable yes/no: on after `sustain` above the threshold,
/// off only after `release` below it, so brief spikes and dips don't flap the hold.
public struct ActivityGate: Sendable {
    public private(set) var isOn = false

    private let threshold: ActivityThreshold
    private var aboveSince: Date?
    private var belowSince: Date?

    public init(threshold: ActivityThreshold) {
        self.threshold = threshold
    }

    @discardableResult
    public mutating func update(value: Double, at now: Date) -> Bool {
        if value > threshold.value {
            belowSince = nil
            let since = aboveSince ?? now
            aboveSince = since
            if !isOn, now.timeIntervalSince(since) >= threshold.sustain { isOn = true }
        } else {
            aboveSince = nil
            let since = belowSince ?? now
            belowSince = since
            if isOn, now.timeIntervalSince(since) >= threshold.release { isOn = false }
        }
        return isOn
    }
}

/// Converts an ever-increasing counter into a per-second rate.
public struct RateMeter: Sendable {
    private var lastValue: UInt64?
    private var lastTime: Date?

    public init() {}

    /// nil on the first sample, when no time has passed, or when the counter went backwards (a reset).
    public mutating func rate(for value: UInt64, at now: Date) -> Double? {
        defer {
            lastValue = value
            lastTime = now
        }
        guard let lastValue, let lastTime, now > lastTime, value >= lastValue else { return nil }
        return Double(value - lastValue) / now.timeIntervalSince(lastTime)
    }
}

/// Converts cumulative CPU ticks into a busy percentage.
public struct CPUMeter: Sendable {
    private var last: (busy: UInt64, total: UInt64)?

    public init() {}

    public mutating func percent(busy: UInt64, total: UInt64) -> Double? {
        defer { last = (busy, total) }
        guard let last, total > last.total, busy >= last.busy else { return nil }
        return Double(busy - last.busy) / Double(total - last.total) * 100
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `make test`
Expected: all `ActivityGateTests` pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/EyesUpCore/Triggers/ActivityGate.swift Tests/EyesUpCoreTests/ActivityGateTests.swift
git commit -m "feat(core): add hysteresis gate and rate meters for activity triggers" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: Trigger holds and the safety cap in AwakeController

**Files:**
- Modify: `Sources/EyesUpCore/Holds/Hold.swift` (add `expiry(safetyCap:)`, extend `awakeUntil`)
- Modify: `Sources/EyesUpCore/Engine/DeadlineMonitor.swift` (honor a cap)
- Modify: `Sources/EyesUpCore/AwakeController.swift` (trigger-hold API, cap, safety release callback)
- Modify: `Tests/EyesUpCoreTests/AwakeControllerTests.swift`

**Interfaces:**
- Consumes: Plan 1's `Hold`, `DeadlineMonitor`, `AwakeController`.
- Produces:
  - `Hold.expiry(safetyCap: TimeInterval?) -> Date?`; `Hold.awakeUntil(_:safetyCap:)`
  - `DeadlineMonitor.safetyCap: TimeInterval?`
  - `AwakeController.safetyCap`, `setSafetyCap(_:)`, `onSafetyRelease: (([String]) -> Void)?`
  - `AwakeController.beginTriggerHold(triggerID:label:policy:) -> Hold`, `endTriggerHold(triggerID:grace:)`, `removeTriggerHolds()`, `hasTriggerHold(triggerID:) -> Bool`, `releaseAllForSafety()`

- [ ] **Step 1: Write the failing tests**

Append inside `@Suite @MainActor struct AwakeControllerTests` in `Tests/EyesUpCoreTests/AwakeControllerTests.swift` (before its closing brace):
```swift
    // MARK: Trigger holds

    @Test func triggerHoldIsNotAManualSessionAndHasNoEnd() {
        let controller = makeController()
        let triggerID = UUID()
        controller.beginTriggerHold(triggerID: triggerID, label: "Claude running", policy: .system)
        #expect(controller.isAwake)
        #expect(controller.awakeUntil == nil)
        #expect(provider.liveNames == ["EyesUpGuardian: Claude running"])

        try? controller.startTimer(duration: 3600, policy: .system)
        #expect(controller.holds.count == 2)
        #expect(controller.hasTriggerHold(triggerID: triggerID))
    }

    @Test func beginningTheSameTriggerTwiceKeepsOneHold() {
        let controller = makeController()
        let triggerID = UUID()
        controller.beginTriggerHold(triggerID: triggerID, label: "A", policy: .system)
        controller.beginTriggerHold(triggerID: triggerID, label: "B", policy: [.system, .display])
        #expect(controller.holds.count == 1)
        #expect(controller.holds.first?.label == "B")
        #expect(provider.liveKinds == [.preventIdleSystemSleep, .preventDisplaySleep])
    }

    @Test func endingATriggerHoldRespectsGrace() {
        let controller = makeController()
        let triggerID = UUID()
        controller.beginTriggerHold(triggerID: triggerID, label: "Build", policy: .system)
        controller.endTriggerHold(triggerID: triggerID, grace: 300)
        #expect(controller.awakeUntil == referenceDate.addingTimeInterval(300))

        clock.advance(300)
        scheduler.runDue(at: clock.now)
        #expect(controller.holds.isEmpty)
        #expect(provider.live.isEmpty)
    }

    @Test func conditionReturningDuringGraceCancelsTheCountdown() {
        let controller = makeController()
        let triggerID = UUID()
        controller.beginTriggerHold(triggerID: triggerID, label: "Build", policy: .system)
        controller.endTriggerHold(triggerID: triggerID, grace: 300)
        controller.beginTriggerHold(triggerID: triggerID, label: "Build", policy: .system)
        #expect(controller.holds.count == 1)
        #expect(controller.awakeUntil == nil)

        clock.advance(600)
        scheduler.runDue(at: clock.now)
        #expect(controller.isAwake)
    }

    @Test func stopAllLeavesTriggerHoldsButRemoveTriggerHoldsClearsThem() {
        let controller = makeController()
        let triggerID = UUID()
        controller.beginTriggerHold(triggerID: triggerID, label: "Claude running", policy: .system)
        try? controller.startTimer(duration: 3600, policy: .system)

        controller.stopAll()
        #expect(controller.holds.map(\.label) == ["Claude running"])

        controller.removeTriggerHolds()
        #expect(controller.holds.isEmpty)
        #expect(provider.live.isEmpty)
    }

    // MARK: Safety cap and emergency release

    @Test func safetyCapEndsAnIndefiniteHoldAndReportsIt() {
        let controller = makeController()
        var released: [String] = []
        controller.onSafetyRelease = { released = $0 }
        controller.setSafetyCap(3600)
        controller.startIndefinite(policy: .system)
        #expect(controller.awakeUntil == referenceDate.addingTimeInterval(3600))

        clock.advance(3600)
        scheduler.runDue(at: clock.now)
        #expect(controller.holds.isEmpty)
        #expect(released == ["Indefinitely"])
        #expect(provider.live.isEmpty)
    }

    @Test func normalExpiryIsNotReportedAsASafetyRelease() throws {
        let controller = makeController()
        var released: [String] = []
        controller.onSafetyRelease = { released = $0 }
        controller.setSafetyCap(3600)
        try controller.startTimer(duration: 1800, policy: .system)

        clock.advance(1800)
        scheduler.runDue(at: clock.now)
        #expect(controller.holds.isEmpty)
        #expect(released.isEmpty)
    }

    @Test func clearingTheSafetyCapRestoresNoEndTime() {
        let controller = makeController()
        controller.setSafetyCap(3600)
        controller.startIndefinite(policy: .system)
        controller.setSafetyCap(nil)
        #expect(controller.awakeUntil == nil)
        clock.advance(7200)
        scheduler.runDue(at: clock.now)
        #expect(controller.isAwake)
    }

    @Test func releaseAllForSafetyDropsEverythingIncludingTriggers() {
        let controller = makeController()
        controller.beginTriggerHold(triggerID: UUID(), label: "Claude running", policy: .system)
        controller.startIndefinite(policy: .system)
        controller.releaseAllForSafety()
        #expect(controller.holds.isEmpty)
        #expect(provider.live.isEmpty)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test`
Expected: FAIL to compile with `value of type 'AwakeController' has no member 'beginTriggerHold'`.

- [ ] **Step 3: Add the cap to `Hold`**

In `Sources/EyesUpCore/Holds/Hold.swift`, replace the `awakeUntil` function with:
```swift
    /// When this hold ends, counting its grace and any safety cap (spec §4.5).
    public func expiry(safetyCap: TimeInterval?) -> Date? {
        let capped = safetyCap.map { createdAt.addingTimeInterval($0) }
        switch (effectiveDeadline, capped) {
        case (let deadline?, let cap?): return min(deadline, cap)
        case (let deadline?, nil): return deadline
        case (nil, let cap?): return cap
        case (nil, nil): return nil
        }
    }

    /// When the Mac may sleep again, or nil if there are no holds or any hold has no end.
    public static func awakeUntil(_ holds: [Hold], safetyCap: TimeInterval? = nil) -> Date? {
        guard !holds.isEmpty else { return nil }
        var latest = Date.distantPast
        for hold in holds {
            guard let end = hold.expiry(safetyCap: safetyCap) else { return nil }
            latest = max(latest, end)
        }
        return latest
    }
```

- [ ] **Step 4: Teach `DeadlineMonitor` about the cap**

In `Sources/EyesUpCore/Engine/DeadlineMonitor.swift`:
1. Add a stored property after `public var headsUpLead: TimeInterval`:
```swift
    /// Spec §4.5: no hold may run longer than this, whatever its own end says.
    public var safetyCap: TimeInterval?
```
2. Replace the three body lines that read a hold's deadline:
```swift
        let expired = holds.filter { ($0.effectiveDeadline ?? .distantFuture) <= now }.map(\.id)
```
with
```swift
        let expired = holds.filter { ($0.expiry(safetyCap: safetyCap) ?? .distantFuture) <= now }.map(\.id)
```
and
```swift
        if let next = holds.compactMap(\.effectiveDeadline).min() {
```
with
```swift
        if let next = holds.compactMap({ $0.expiry(safetyCap: safetyCap) }).min() {
```
and
```swift
        guard let end = Hold.awakeUntil(holds), end != announcedEnd else { return }
```
with
```swift
        guard let end = Hold.awakeUntil(holds, safetyCap: safetyCap), end != announcedEnd else { return }
```

- [ ] **Step 5: Add the controller API**

In `Sources/EyesUpCore/AwakeController.swift`:

1. Replace `public var awakeUntil: Date? { Hold.awakeUntil(holds) }` with:
```swift
    public var awakeUntil: Date? { Hold.awakeUntil(holds, safetyCap: safetyCap) }
    /// Spec §4.5 safety cap, in seconds; nil means no cap.
    public private(set) var safetyCap: TimeInterval?
    /// Labels of holds the safety cap ended, for the notification.
    @ObservationIgnored public var onSafetyRelease: (([String]) -> Void)?
```

2. Replace the `deadlines.onExpired` line in `init` with:
```swift
        deadlines.onExpired = { [weak self] ids in self?.expire(ids: Set(ids)) }
```

3. Add these methods just above `// MARK: Lifecycle`:
```swift
    // MARK: Trigger holds

    /// Takes (or refreshes) the hold a trigger owns. Trigger holds have no end of their own.
    @discardableResult
    public func beginTriggerHold(triggerID: UUID, label: String, policy: SleepPolicy) -> Hold {
        if let index = holds.firstIndex(where: { $0.source == .trigger(triggerID) }) {
            holds[index].end = .triggerControlled // cancels any grace countdown
            holds[index].label = label
            holds[index].policy = policy
            commit()
            return holds[index]
        }
        let hold = Hold(source: .trigger(triggerID), label: label, policy: policy,
                        end: .triggerControlled, createdAt: clock.now)
        holds.append(hold)
        commit()
        return hold
    }

    /// The trigger's condition ended: drop the hold now, or after its grace period.
    public func endTriggerHold(triggerID: UUID, grace: TimeInterval) {
        guard let index = holds.firstIndex(where: { $0.source == .trigger(triggerID) }) else { return }
        guard grace > 0 else {
            remove(ids: [holds[index].id])
            return
        }
        holds[index].end = .deadline(clock.now.addingTimeInterval(grace))
        commit()
    }

    public func removeTriggerHolds() {
        remove(ids: Set(holds.filter(\.source.isTrigger).map(\.id)))
    }

    public func hasTriggerHold(triggerID: UUID) -> Bool {
        holds.contains { $0.source == .trigger(triggerID) }
    }

    // MARK: Safety

    public func setSafetyCap(_ cap: TimeInterval?) {
        safetyCap = cap.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        deadlines.safetyCap = safetyCap
        commit()
    }

    /// Thermal emergency (spec §4.5): drop every hold, whatever its source.
    public func releaseAllForSafety() {
        holds.removeAll()
        commit()
    }
```

4. Add this private method right above `private func commit()`:
```swift
    /// Holds whose own end has not arrived were ended by the safety cap, so the user is told.
    private func expire(ids: Set<UUID>) {
        let now = clock.now
        let capped = holds.filter { ids.contains($0.id) && ($0.effectiveDeadline ?? .distantFuture) > now }
        remove(ids: ids)
        if !capped.isEmpty { onSafetyRelease?(capped.map(\.label)) }
    }
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `make test`
Expected: all `AwakeControllerTests` pass, including the 9 new ones, and Plan 1's other suites stay green.

- [ ] **Step 7: Commit**

```bash
git add Sources/EyesUpCore Tests/EyesUpCoreTests/AwakeControllerTests.swift
git commit -m "feat(core): add trigger-owned holds, safety cap and emergency release" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: TriggerEngine

**Files:**
- Create: `Sources/EyesUpCore/Triggers/ConditionMonitor.swift`, `Sources/EyesUpCore/Triggers/TriggerEngine.swift`, `Tests/EyesUpCoreTests/TriggerEngineTests.swift`
- Modify: `Tests/EyesUpCoreTests/Support/TriggerFakes.swift` (append `FakeConditionMonitor`, `FakeMonitorFactory`)

**Interfaces:**
- Consumes: `Trigger`, `TriggerValidator`, `AwakeController` trigger API (Task 4), `JSONFileStore`, `WallClock`, `TimerScheduling`, `ScheduledTask`.
- Produces:
  - `@MainActor protocol ConditionMonitor { func start(_ report: @escaping @MainActor (Bool) -> Void); func stop(); func reevaluate() }`
  - `@MainActor protocol ConditionMonitorFactory { func makeMonitor(for: TriggerCondition) -> any ConditionMonitor }`
  - `enum TriggerPause: Codable, Hashable, Sendable { case none, untilResumed, until(Date) }`
  - `enum TriggerError: Error { case invalid }` with `message`
  - `@MainActor @Observable final class TriggerEngine`: `triggers`, `pause`, `isPaused`, `storeNotice`, `onNotify`, `init(controller:factory:clock:scheduler:store:)`, `load()`, `add(_:) throws`, `update(_:) throws`, `remove(id:)`, `setEnabled(_:id:)`, `setPause(_:)`, `refresh()`, `shutdown()`

- [ ] **Step 1: Write the fakes and failing tests**

Append to `Tests/EyesUpCoreTests/Support/TriggerFakes.swift`:
```swift
@MainActor
final class FakeConditionMonitor: ConditionMonitor {
    let condition: TriggerCondition
    private(set) var isStarted = false
    private(set) var reevaluateCount = 0
    private var report: (@MainActor (Bool) -> Void)?

    init(condition: TriggerCondition) { self.condition = condition }

    func start(_ report: @escaping @MainActor (Bool) -> Void) {
        isStarted = true
        self.report = report
    }

    func stop() {
        isStarted = false
        report = nil
    }

    func reevaluate() { reevaluateCount += 1 }

    /// Test hook: pretend the condition changed.
    func send(_ met: Bool) { report?(met) }
}

@MainActor
final class FakeMonitorFactory: ConditionMonitorFactory {
    private(set) var made: [FakeConditionMonitor] = []

    func makeMonitor(for condition: TriggerCondition) -> any ConditionMonitor {
        let monitor = FakeConditionMonitor(condition: condition)
        made.append(monitor)
        return monitor
    }

    var last: FakeConditionMonitor? { made.last }
}
```

`Tests/EyesUpCoreTests/TriggerEngineTests.swift`:
```swift
import Foundation
import Testing
@testable import EyesUpCore

@Suite @MainActor struct TriggerEngineTests {
    let provider = FakePowerAssertions()
    let clock = FakeClock()
    let scheduler = FakeScheduler()
    let factory = FakeMonitorFactory()

    func makeController() -> AwakeController {
        AwakeController(provider: provider, clock: clock, scheduler: scheduler,
                        exitWatcher: FakeExitWatcher(), inspector: FakeInspector(), holdStore: nil)
    }

    func makeEngine(controller: AwakeController, store: JSONFileStore<[Trigger]>? = nil) -> TriggerEngine {
        TriggerEngine(controller: controller, factory: factory, clock: clock, scheduler: scheduler, store: store)
    }

    func tempStore() -> JSONFileStore<[Trigger]> {
        JSONFileStore(
            url: FileManager.default.temporaryDirectory.appendingPathComponent("EyesUpTests-\(UUID().uuidString)/triggers.json"),
            schemaVersion: 1
        )
    }

    @Test func aTrueConditionTakesAHold() throws {
        let controller = makeController()
        let engine = makeEngine(controller: controller)
        let trigger = makeTrigger(name: "Claude running")
        try engine.add(trigger)

        factory.last?.send(true)
        #expect(controller.hasTriggerHold(triggerID: trigger.id))
        #expect(provider.liveNames == ["EyesUpGuardian: Claude running"])
    }

    @Test func repeatedReportsDoNotDuplicateHolds() throws {
        let controller = makeController()
        let engine = makeEngine(controller: controller)
        try engine.add(makeTrigger())
        factory.last?.send(true)
        factory.last?.send(true)
        factory.last?.send(true)
        #expect(controller.holds.count == 1)
        #expect(provider.createCount == 1)
    }

    @Test func aFalseConditionReleasesAfterGrace() throws {
        let controller = makeController()
        let engine = makeEngine(controller: controller)
        try engine.add(makeTrigger(grace: 300))
        factory.last?.send(true)
        factory.last?.send(false)
        #expect(controller.isAwake)

        clock.advance(300)
        scheduler.runDue(at: clock.now)
        #expect(controller.holds.isEmpty)
    }

    @Test func conditionReturningDuringGraceKeepsOneHold() throws {
        let controller = makeController()
        let engine = makeEngine(controller: controller)
        try engine.add(makeTrigger(grace: 300))
        factory.last?.send(true)
        factory.last?.send(false)
        factory.last?.send(true)
        clock.advance(600)
        scheduler.runDue(at: clock.now)
        #expect(controller.holds.count == 1)
    }

    @Test func disablingATriggerStopsItsMonitorAndDropsItsHold() throws {
        let controller = makeController()
        let engine = makeEngine(controller: controller)
        let trigger = makeTrigger(grace: 300)
        try engine.add(trigger)
        factory.last?.send(true)

        engine.setEnabled(false, id: trigger.id)
        #expect(controller.holds.isEmpty)
        #expect(factory.last?.isStarted == false)
        #expect(engine.triggers.first?.isEnabled == false)
    }

    @Test func aDisabledTriggerNeverStartsAMonitor() throws {
        let engine = makeEngine(controller: makeController())
        try engine.add(makeTrigger(isEnabled: false))
        #expect(factory.made.isEmpty)
    }

    @Test func removingATriggerDropsItsHold() throws {
        let controller = makeController()
        let engine = makeEngine(controller: controller)
        let trigger = makeTrigger()
        try engine.add(trigger)
        factory.last?.send(true)

        engine.remove(id: trigger.id)
        #expect(controller.holds.isEmpty)
        #expect(engine.triggers.isEmpty)
    }

    @Test func updatingATriggerRestartsItsMonitor() throws {
        let controller = makeController()
        let engine = makeEngine(controller: controller)
        var trigger = makeTrigger(condition: .onACPower)
        try engine.add(trigger)
        factory.last?.send(true)

        trigger.condition = .processRunning(names: ["node"])
        try engine.update(trigger)
        #expect(controller.holds.isEmpty)          // the old hold went with the old condition
        #expect(factory.made.count == 2)
        #expect(factory.made.first?.isStarted == false)
        if case .processRunning = factory.last?.condition {} else { Issue.record("monitor not rebuilt") }
    }

    @Test func invalidTriggersAreRejected() {
        let engine = makeEngine(controller: makeController())
        #expect(throws: TriggerError.invalid) { try engine.add(makeTrigger(name: " ")) }
        #expect(engine.triggers.isEmpty)
    }

    @Test func pauseDropsHoldsAndIgnoresReports() throws {
        let controller = makeController()
        let engine = makeEngine(controller: controller)
        try engine.add(makeTrigger())
        factory.last?.send(true)

        engine.setPause(.untilResumed)
        #expect(controller.holds.isEmpty)
        factory.last?.send(false)
        factory.last?.send(true)
        #expect(controller.holds.isEmpty)
    }

    @Test func resumeReappliesStillTrueConditions() throws {
        let controller = makeController()
        let engine = makeEngine(controller: controller)
        try engine.add(makeTrigger())
        factory.last?.send(true)
        engine.setPause(.untilResumed)
        engine.setPause(.none)
        #expect(controller.holds.count == 1)
    }

    @Test func aTimedPauseResumesOnSchedule() throws {
        let controller = makeController()
        let engine = makeEngine(controller: controller)
        try engine.add(makeTrigger())
        factory.last?.send(true)

        engine.setPause(.until(referenceDate.addingTimeInterval(3600)))
        #expect(controller.holds.isEmpty)
        clock.advance(3600)
        scheduler.runDue(at: clock.now)
        #expect(engine.pause == .none)
        #expect(controller.holds.count == 1)
    }

    @Test func refreshResumesAPauseThatExpiredWhileAsleep() throws {
        let controller = makeController()
        let engine = makeEngine(controller: controller)
        try engine.add(makeTrigger())
        factory.last?.send(true)
        engine.setPause(.until(referenceDate.addingTimeInterval(3600)))

        clock.advance(7200) // the Mac slept through the resume time
        engine.refresh()
        #expect(engine.pause == .none)
        #expect(controller.holds.count == 1)
        #expect(factory.last?.reevaluateCount == 1)
    }

    @Test func notifyOnChangeReportsBothEdges() throws {
        let engine = makeEngine(controller: makeController())
        var messages: [String] = []
        engine.onNotify = { messages.append($0) }
        try engine.add(makeTrigger(name: "Claude running", notifyOnChange: true))
        factory.last?.send(true)
        factory.last?.send(false)
        #expect(messages.count == 2)
        #expect(messages.allSatisfy { $0.contains("Claude running") })
    }

    @Test func loadDropsInvalidTriggersWithNotice() throws {
        let store = tempStore()
        try store.save([makeTrigger(name: "Good"), makeTrigger(name: " "), makeTrigger(grace: 99_999)])
        let engine = makeEngine(controller: makeController(), store: store)
        engine.load()
        #expect(engine.triggers.map(\.name) == ["Good"])
        #expect(engine.storeNotice != nil)
        #expect(factory.made.count == 1)
    }

    @Test func loadReportsCorruptStore() throws {
        let store = tempStore()
        try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("nonsense".utf8).write(to: store.url)
        let engine = makeEngine(controller: makeController(), store: store)
        engine.load()
        #expect(engine.triggers.isEmpty)
        #expect(engine.storeNotice != nil)
    }

    @Test func triggersSurviveARestart() throws {
        let store = tempStore()
        let first = makeEngine(controller: makeController(), store: store)
        try first.add(makeTrigger(name: "Claude running"))

        let second = TriggerEngine(controller: makeController(), factory: FakeMonitorFactory(),
                                   clock: clock, scheduler: scheduler, store: store)
        second.load()
        #expect(second.triggers.map(\.name) == ["Claude running"])
    }

    @Test func shutdownStopsMonitorsAndLeavesHoldsToTheController() throws {
        let controller = makeController()
        let engine = makeEngine(controller: controller)
        try engine.add(makeTrigger())
        factory.last?.send(true)
        engine.shutdown()
        #expect(factory.last?.isStarted == false)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test`
Expected: FAIL to compile with `cannot find type 'ConditionMonitor' in scope`.

- [ ] **Step 3: Write the protocols**

`Sources/EyesUpCore/Triggers/ConditionMonitor.swift`:
```swift
import Foundation

/// Watches one trigger's condition and reports its answer: once at `start`, then on every change.
@MainActor
public protocol ConditionMonitor: AnyObject {
    func start(_ report: @escaping @MainActor (Bool) -> Void)
    func stop()
    /// Re-check after a wake, clock change or timezone change.
    func reevaluate()
}

@MainActor
public protocol ConditionMonitorFactory: AnyObject {
    func makeMonitor(for condition: TriggerCondition) -> any ConditionMonitor
}
```

- [ ] **Step 4: Write the engine**

`Sources/EyesUpCore/Triggers/TriggerEngine.swift`:
```swift
import Foundation
import Observation

/// Whether triggers are paused, and until when (spec §4.5).
public enum TriggerPause: Codable, Hashable, Sendable {
    case none
    case untilResumed
    case until(Date)
}

public enum TriggerError: Error, Equatable, Sendable {
    case invalid

    public var message: String { "Check the trigger's name and settings — something is missing or out of range." }
}

/// Turns condition changes into trigger-owned holds on the controller (spec §5).
@MainActor
@Observable
public final class TriggerEngine {
    public private(set) var triggers: [Trigger] = []
    public private(set) var pause: TriggerPause = .none
    public private(set) var storeNotice: String?

    public var isPaused: Bool { pause != .none }

    /// Messages for triggers whose `notifyOnChange` is on.
    @ObservationIgnored public var onNotify: ((String) -> Void)?

    @ObservationIgnored private let controller: AwakeController
    @ObservationIgnored private let factory: any ConditionMonitorFactory
    @ObservationIgnored private let clock: any WallClock
    @ObservationIgnored private let scheduler: any TimerScheduling
    @ObservationIgnored private let store: JSONFileStore<[Trigger]>?
    @ObservationIgnored private var monitors: [UUID: any ConditionMonitor] = [:]
    @ObservationIgnored private var conditionMet: [UUID: Bool] = [:]
    @ObservationIgnored private var resumeTask: (any ScheduledTask)?

    public init(
        controller: AwakeController,
        factory: any ConditionMonitorFactory,
        clock: any WallClock = SystemClock(),
        scheduler: any TimerScheduling,
        store: JSONFileStore<[Trigger]>? = nil
    ) {
        self.controller = controller
        self.factory = factory
        self.clock = clock
        self.scheduler = scheduler
        self.store = store
    }

    // MARK: Lifecycle

    /// Reads saved triggers (dropping any that fail validation) and starts their monitors.
    public func load() {
        if let store {
            switch store.load(now: clock.now) {
            case .missing:
                break
            case .loaded(let saved):
                let valid = saved.compactMap(TriggerValidator.sanitized)
                if valid.count < saved.count {
                    storeNotice = "Some saved triggers were invalid and were discarded."
                }
                triggers = valid
            case .corrupt:
                storeNotice = "Saved triggers couldn't be read, so they were reset."
            }
        }
        for trigger in triggers { startMonitor(for: trigger) }
    }

    public func shutdown() {
        resumeTask?.cancel()
        resumeTask = nil
        for monitor in monitors.values { monitor.stop() }
        monitors.removeAll()
        conditionMet.removeAll()
    }

    /// Re-check everything after a wake, clock change or timezone change.
    public func refresh() {
        if case .until(let date) = pause, date <= clock.now { setPause(.none) }
        for monitor in monitors.values { monitor.reevaluate() }
    }

    // MARK: Editing

    public func add(_ trigger: Trigger) throws {
        guard let clean = TriggerValidator.sanitized(trigger) else { throw TriggerError.invalid }
        triggers.append(clean)
        startMonitor(for: clean)
        persist()
    }

    public func update(_ trigger: Trigger) throws {
        guard let clean = TriggerValidator.sanitized(trigger),
              let index = triggers.firstIndex(where: { $0.id == clean.id }) else { throw TriggerError.invalid }
        triggers[index] = clean
        startMonitor(for: clean) // stops the old monitor and drops its hold first
        persist()
    }

    public func remove(id: UUID) {
        triggers.removeAll { $0.id == id }
        stopMonitor(id: id)
        persist()
    }

    public func setEnabled(_ enabled: Bool, id: UUID) {
        guard let index = triggers.firstIndex(where: { $0.id == id }) else { return }
        triggers[index].isEnabled = enabled
        if enabled { startMonitor(for: triggers[index]) } else { stopMonitor(id: id) }
        persist()
    }

    // MARK: Pausing

    public func setPause(_ newPause: TriggerPause) {
        resumeTask?.cancel()
        resumeTask = nil
        pause = newPause

        switch newPause {
        case .none:
            for trigger in triggers where trigger.isEnabled && conditionMet[trigger.id] == true {
                apply(trigger, met: true)
            }
        case .untilResumed:
            controller.removeTriggerHolds()
        case .until(let date):
            controller.removeTriggerHolds()
            resumeTask = scheduler.schedule(at: date) { [weak self] in self?.setPause(.none) }
        }
    }

    // MARK: Private

    private func startMonitor(for trigger: Trigger) {
        stopMonitor(id: trigger.id)
        guard trigger.isEnabled else { return }
        let monitor = factory.makeMonitor(for: trigger.condition)
        monitors[trigger.id] = monitor
        monitor.start { [weak self] met in self?.report(triggerID: trigger.id, met: met) }
    }

    private func stopMonitor(id: UUID) {
        monitors.removeValue(forKey: id)?.stop()
        conditionMet[id] = nil
        controller.endTriggerHold(triggerID: id, grace: 0)
    }

    private func report(triggerID: UUID, met: Bool) {
        guard let trigger = triggers.first(where: { $0.id == triggerID }), trigger.isEnabled else { return }
        guard conditionMet[triggerID] != met else { return } // only edges matter
        conditionMet[triggerID] = met
        guard !isPaused else { return }
        apply(trigger, met: met)
    }

    private func apply(_ trigger: Trigger, met: Bool) {
        if met {
            controller.beginTriggerHold(triggerID: trigger.id, label: trigger.name, policy: trigger.policy)
            if trigger.notifyOnChange { onNotify?("\(trigger.name): keeping your Mac awake.") }
        } else {
            controller.endTriggerHold(triggerID: trigger.id, grace: trigger.grace)
            if trigger.notifyOnChange { onNotify?("\(trigger.name): stopped keeping your Mac awake.") }
        }
    }

    private func persist() {
        guard let store else { return }
        do {
            try store.save(triggers)
        } catch {
            storeNotice = "Couldn't save triggers: \(error.localizedDescription)"
        }
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `make test`
Expected: all 18 `TriggerEngineTests` pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/EyesUpCore/Triggers Tests/EyesUpCoreTests
git commit -m "feat(core): add trigger engine with grace periods, pausing and persistence" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: Event-driven monitors (app, display, power, schedule)

**Files:**
- Create: `Sources/EyesUpCore/Triggers/SystemSources.swift`, `Sources/EyesUpCore/Triggers/EventMonitors.swift`, `Tests/EyesUpCoreTests/EventMonitorTests.swift`
- Modify: `Tests/EyesUpCoreTests/Support/TriggerFakes.swift` (append the system-source fakes)

**Interfaces:**
- Consumes: `ConditionMonitor`, `Schedule.isActive/nextBoundary`, `DisplayMatch`, `WallClock`, `TimerScheduling`, `ScheduledTask`.
- Produces:
  - `@MainActor protocol WorkspaceEvents { func runningBundleIDs() -> Set<String>; func observeChanges(_:) -> any ScheduledTask }`
  - `@MainActor protocol DisplayInventory { func connectedDisplays() -> [DisplayMatch]; func observeChanges(_:) -> any ScheduledTask }`
  - `@MainActor protocol PowerSourceInfo { func isOnACPower() -> Bool; func observeChanges(_:) -> any ScheduledTask }`
  - `protocol ProcessLister: Sendable { func runningProcessNames() -> Set<String> }`
  - `protocol SystemCounters: Sendable { func cpuTicks() -> (busy: UInt64, total: UInt64)?; func networkBytes() -> UInt64?; func diskBytesWritten() -> UInt64? }`
  - `enum ThermalLevel: Int, Comparable { nominal, fair, serious, critical }`, `@MainActor protocol ThermalMonitoring { func currentLevel() -> ThermalLevel; func observeChanges(_:) -> any ScheduledTask }`
  - `AppRunningMonitor(bundleIDs:workspace:)`, `DisplayConnectedMonitor(match:displays:)`, `PowerSourceMonitor(power:)`, `ScheduleMonitor(schedule:clock:scheduler:calendar:)`

- [ ] **Step 1: Write the fakes and failing tests**

Append to `Tests/EyesUpCoreTests/Support/TriggerFakes.swift`:
```swift
@MainActor
final class FakeWorkspace: WorkspaceEvents {
    var running: Set<String> = []
    private var handler: (@MainActor () -> Void)?

    func runningBundleIDs() -> Set<String> { running }

    func observeChanges(_ handler: @escaping @MainActor () -> Void) -> any ScheduledTask {
        self.handler = handler
        return FakeTask { [weak self] in self?.handler = nil }
    }

    /// Test hook: pretend an app launched or quit.
    func change(to running: Set<String>) {
        self.running = running
        handler?()
    }
}

@MainActor
final class FakeDisplays: DisplayInventory {
    var connected: [DisplayMatch] = []
    private var handler: (@MainActor () -> Void)?

    func connectedDisplays() -> [DisplayMatch] { connected }

    func observeChanges(_ handler: @escaping @MainActor () -> Void) -> any ScheduledTask {
        self.handler = handler
        return FakeTask { [weak self] in self?.handler = nil }
    }

    func change(to connected: [DisplayMatch]) {
        self.connected = connected
        handler?()
    }
}

@MainActor
final class FakePowerSource: PowerSourceInfo {
    var onAC = true
    private var handler: (@MainActor () -> Void)?

    func isOnACPower() -> Bool { onAC }

    func observeChanges(_ handler: @escaping @MainActor () -> Void) -> any ScheduledTask {
        self.handler = handler
        return FakeTask { [weak self] in self?.handler = nil }
    }

    func change(to onAC: Bool) {
        self.onAC = onAC
        handler?()
    }
}

final class FakeProcessLister: ProcessLister, @unchecked Sendable {
    var names: Set<String> = []
    func runningProcessNames() -> Set<String> { names }
}

final class FakeCounters: SystemCounters, @unchecked Sendable {
    var cpu: (busy: UInt64, total: UInt64)?
    var network: UInt64?
    var disk: UInt64?

    func cpuTicks() -> (busy: UInt64, total: UInt64)? { cpu }
    func networkBytes() -> UInt64? { network }
    func diskBytesWritten() -> UInt64? { disk }
}

@MainActor
final class FakeThermal: ThermalMonitoring {
    var level: ThermalLevel = .nominal
    private var handler: (@MainActor () -> Void)?

    func currentLevel() -> ThermalLevel { level }

    func observeChanges(_ handler: @escaping @MainActor () -> Void) -> any ScheduledTask {
        self.handler = handler
        return FakeTask { [weak self] in self?.handler = nil }
    }

    func change(to level: ThermalLevel) {
        self.level = level
        handler?()
    }
}
```

`Tests/EyesUpCoreTests/EventMonitorTests.swift`:
```swift
import Foundation
import Testing
@testable import EyesUpCore

@Suite @MainActor struct EventMonitorTests {
    let clock = FakeClock()
    let scheduler = FakeScheduler()

    // MARK: Apps

    @Test func appMonitorReportsWhileAnyChosenAppIsOpen() {
        let workspace = FakeWorkspace()
        workspace.running = ["com.apple.Terminal"]
        let monitor = AppRunningMonitor(bundleIDs: ["com.anthropic.claudefordesktop", "com.apple.Terminal"], workspace: workspace)
        var answers: [Bool] = []
        monitor.start { answers.append($0) }
        #expect(answers == [true])

        workspace.change(to: ["com.apple.Finder"])
        #expect(answers == [true, false])

        workspace.change(to: ["com.anthropic.claudefordesktop"])
        #expect(answers == [true, false, true])
    }

    @Test func appMonitorStopsListening() {
        let workspace = FakeWorkspace()
        let monitor = AppRunningMonitor(bundleIDs: ["com.apple.Terminal"], workspace: workspace)
        var count = 0
        monitor.start { _ in count += 1 }
        monitor.stop()
        workspace.change(to: ["com.apple.Terminal"])
        #expect(count == 1) // only the initial answer
    }

    // MARK: Displays

    @Test func displayMonitorMatchesOnVendorModelSerial() {
        let studioDisplay = DisplayMatch(vendor: 7789, model: 30734, serial: 47852, name: "LG UltraFine")
        let otherDisplay = DisplayMatch(vendor: 1, model: 2, serial: 3, name: "Other")
        let displays = FakeDisplays()
        displays.connected = [otherDisplay]
        let monitor = DisplayConnectedMonitor(match: studioDisplay, displays: displays)
        var answers: [Bool] = []
        monitor.start { answers.append($0) }
        #expect(answers == [false])

        displays.change(to: [otherDisplay, DisplayMatch(vendor: 7789, model: 30734, serial: 47852, name: "renamed")])
        #expect(answers == [false, true])
    }

    // MARK: Power

    @Test func powerMonitorFollowsTheSource() {
        let power = FakePowerSource()
        power.onAC = false
        let monitor = PowerSourceMonitor(power: power)
        var answers: [Bool] = []
        monitor.start { answers.append($0) }
        #expect(answers == [false])

        power.change(to: true)
        #expect(answers == [false, true])
    }

    // MARK: Schedule

    /// 2026-09-21 09:00 local, a Monday.
    private func mondayMorning() -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 8, minute: 0))!
    }

    private func newYork() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    @Test func scheduleMonitorReportsAndArmsTheNextBoundary() {
        clock.now = mondayMorning()
        let schedule = Schedule(weekdays: [2, 3, 4, 5, 6], startMinute: 9 * 60, endMinute: 18 * 60)
        let calendar = newYork()
        let monitor = ScheduleMonitor(schedule: schedule, clock: clock, scheduler: scheduler, calendar: { calendar })
        var answers: [Bool] = []
        monitor.start { answers.append($0) }
        #expect(answers == [false])

        clock.advance(3600) // 09:00
        scheduler.runDue(at: clock.now)
        #expect(answers == [false, true])
    }

    @Test func scheduleMonitorReevaluatesOnDemand() {
        clock.now = mondayMorning()
        let schedule = Schedule(weekdays: [2, 3, 4, 5, 6], startMinute: 9 * 60, endMinute: 18 * 60)
        let calendar = newYork()
        let monitor = ScheduleMonitor(schedule: schedule, clock: clock, scheduler: scheduler, calendar: { calendar })
        var answers: [Bool] = []
        monitor.start { answers.append($0) }

        clock.advance(7200) // the Mac slept past 09:00; no timer fired
        monitor.reevaluate()
        #expect(answers == [false, true])
    }

    @Test func scheduleMonitorStopsItsTimer() {
        clock.now = mondayMorning()
        let calendar = newYork()
        let monitor = ScheduleMonitor(schedule: Schedule(weekdays: [2], startMinute: 9 * 60, endMinute: 18 * 60),
                                      clock: clock, scheduler: scheduler, calendar: { calendar })
        monitor.start { _ in }
        monitor.stop()
        #expect(scheduler.pending.isEmpty)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test`
Expected: FAIL to compile with `cannot find type 'WorkspaceEvents' in scope`.

- [ ] **Step 3: Write the system-source protocols**

`Sources/EyesUpCore/Triggers/SystemSources.swift`:
```swift
import Foundation

/// Running applications. Implemented in the app layer with NSWorkspace, which is AppKit.
@MainActor
public protocol WorkspaceEvents: AnyObject {
    func runningBundleIDs() -> Set<String>
    func observeChanges(_ handler: @escaping @MainActor () -> Void) -> any ScheduledTask
}

@MainActor
public protocol DisplayInventory: AnyObject {
    func connectedDisplays() -> [DisplayMatch]
    func observeChanges(_ handler: @escaping @MainActor () -> Void) -> any ScheduledTask
}

@MainActor
public protocol PowerSourceInfo: AnyObject {
    func isOnACPower() -> Bool
    func observeChanges(_ handler: @escaping @MainActor () -> Void) -> any ScheduledTask
}

/// Names of processes this user can see. macOS hides other users' and root's names from libproc.
public protocol ProcessLister: Sendable {
    func runningProcessNames() -> Set<String>
}

/// Raw counters behind the activity triggers.
public protocol SystemCounters: Sendable {
    func cpuTicks() -> (busy: UInt64, total: UInt64)?
    func networkBytes() -> UInt64?
    func diskBytesWritten() -> UInt64?
}

public enum ThermalLevel: Int, Sendable, Comparable, CaseIterable {
    case nominal, fair, serious, critical

    public static func < (lhs: ThermalLevel, rhs: ThermalLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

@MainActor
public protocol ThermalMonitoring: AnyObject {
    func currentLevel() -> ThermalLevel
    func observeChanges(_ handler: @escaping @MainActor () -> Void) -> any ScheduledTask
}
```

- [ ] **Step 4: Write the event-driven monitors**

`Sources/EyesUpCore/Triggers/EventMonitors.swift`:
```swift
import Foundation

/// True while any of the chosen apps is running. Bundle IDs can't be spoofed by renaming an app.
@MainActor
public final class AppRunningMonitor: ConditionMonitor {
    private let bundleIDs: Set<String>
    private let workspace: any WorkspaceEvents
    private var report: (@MainActor (Bool) -> Void)?
    private var observation: (any ScheduledTask)?

    public init(bundleIDs: [String], workspace: any WorkspaceEvents) {
        self.bundleIDs = Set(bundleIDs)
        self.workspace = workspace
    }

    public func start(_ report: @escaping @MainActor (Bool) -> Void) {
        self.report = report
        observation = workspace.observeChanges { [weak self] in self?.evaluate() }
        evaluate()
    }

    public func stop() {
        observation?.cancel()
        observation = nil
        report = nil
    }

    public func reevaluate() { evaluate() }

    private func evaluate() {
        report?(!workspace.runningBundleIDs().isDisjoint(with: bundleIDs))
    }
}

/// True while a particular display is plugged in.
@MainActor
public final class DisplayConnectedMonitor: ConditionMonitor {
    private let match: DisplayMatch
    private let displays: any DisplayInventory
    private var report: (@MainActor (Bool) -> Void)?
    private var observation: (any ScheduledTask)?

    public init(match: DisplayMatch, displays: any DisplayInventory) {
        self.match = match
        self.displays = displays
    }

    public func start(_ report: @escaping @MainActor (Bool) -> Void) {
        self.report = report
        observation = displays.observeChanges { [weak self] in self?.evaluate() }
        evaluate()
    }

    public func stop() {
        observation?.cancel()
        observation = nil
        report = nil
    }

    public func reevaluate() { evaluate() }

    private func evaluate() {
        report?(displays.connectedDisplays().contains { $0.matches(match) })
    }
}

/// True while the Mac is on AC power (always true for a desktop; useful for laptops).
@MainActor
public final class PowerSourceMonitor: ConditionMonitor {
    private let power: any PowerSourceInfo
    private var report: (@MainActor (Bool) -> Void)?
    private var observation: (any ScheduledTask)?

    public init(power: any PowerSourceInfo) {
        self.power = power
    }

    public func start(_ report: @escaping @MainActor (Bool) -> Void) {
        self.report = report
        observation = power.observeChanges { [weak self] in self?.evaluate() }
        evaluate()
    }

    public func stop() {
        observation?.cancel()
        observation = nil
        report = nil
    }

    public func reevaluate() { evaluate() }

    private func evaluate() { report?(power.isOnACPower()) }
}

/// True inside the schedule's window. One timer is armed for the next boundary.
@MainActor
public final class ScheduleMonitor: ConditionMonitor {
    private let schedule: Schedule
    private let clock: any WallClock
    private let scheduler: any TimerScheduling
    /// Read fresh each time so a timezone change is picked up.
    private let calendar: @MainActor () -> Calendar
    private var report: (@MainActor (Bool) -> Void)?
    private var task: (any ScheduledTask)?

    public init(
        schedule: Schedule,
        clock: any WallClock,
        scheduler: any TimerScheduling,
        calendar: @escaping @MainActor () -> Calendar = { Calendar.current }
    ) {
        self.schedule = schedule
        self.clock = clock
        self.scheduler = scheduler
        self.calendar = calendar
    }

    public func start(_ report: @escaping @MainActor (Bool) -> Void) {
        self.report = report
        evaluate()
    }

    public func stop() {
        task?.cancel()
        task = nil
        report = nil
    }

    public func reevaluate() { evaluate() }

    private func evaluate() {
        task?.cancel()
        task = nil
        let now = clock.now
        let currentCalendar = calendar()
        report?(schedule.isActive(at: now, calendar: currentCalendar))
        if let next = schedule.nextBoundary(after: now, calendar: currentCalendar) {
            task = scheduler.schedule(at: next) { [weak self] in self?.evaluate() }
        }
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `make test`
Expected: all 7 `EventMonitorTests` pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/EyesUpCore/Triggers Tests/EyesUpCoreTests
git commit -m "feat(core): add app, display, power and schedule condition monitors" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 7: Polling monitors (process running, activity)

**Files:**
- Create: `Sources/EyesUpCore/Triggers/PollingMonitors.swift`, `Tests/EyesUpCoreTests/PollingMonitorTests.swift`

**Interfaces:**
- Consumes: `ProcessLister`, `SystemCounters`, `ActivityGate`, `RateMeter`, `CPUMeter`, `WallClock`, `TimerScheduling`.
- Produces:
  - `ProcessRunningMonitor(names:lister:clock:scheduler:)` with `static let interval: TimeInterval = 10`
  - `ActivityMonitor(kind:threshold:counters:clock:scheduler:)` with `enum Kind { cpu, network, disk }` and `static let interval: TimeInterval = 15`

- [ ] **Step 1: Write the failing tests**

`Tests/EyesUpCoreTests/PollingMonitorTests.swift`:
```swift
import Foundation
import Testing
@testable import EyesUpCore

@Suite @MainActor struct PollingMonitorTests {
    let clock = FakeClock()
    let scheduler = FakeScheduler()

    @Test func processMonitorPollsAndMatchesCaseInsensitively() {
        let lister = FakeProcessLister()
        lister.names = ["Finder"]
        let monitor = ProcessRunningMonitor(names: ["node", "Claude"], lister: lister, clock: clock, scheduler: scheduler)
        var answers: [Bool] = []
        monitor.start { answers.append($0) }
        #expect(answers == [false])

        lister.names = ["Finder", "claude"]
        clock.advance(ProcessRunningMonitor.interval)
        scheduler.runDue(at: clock.now)
        #expect(answers == [false, true])

        lister.names = ["Finder"]
        clock.advance(ProcessRunningMonitor.interval)
        scheduler.runDue(at: clock.now)
        #expect(answers == [false, true, false])
    }

    @Test func processMonitorStopsPolling() {
        let lister = FakeProcessLister()
        let monitor = ProcessRunningMonitor(names: ["node"], lister: lister, clock: clock, scheduler: scheduler)
        monitor.start { _ in }
        monitor.stop()
        #expect(scheduler.pending.isEmpty)
    }

    @Test func cpuActivityMonitorNeedsSustainedLoad() {
        let counters = FakeCounters()
        counters.cpu = (busy: 0, total: 1000)
        let monitor = ActivityMonitor(
            kind: .cpu, threshold: ActivityThreshold(value: 40, sustain: 30, release: 30),
            counters: counters, clock: clock, scheduler: scheduler
        )
        var answers: [Bool] = []
        monitor.start { answers.append($0) }
        #expect(answers == [false]) // no baseline yet

        // Each tick: 90 busy ticks out of 100 = 90%.
        for step in 1...3 {
            counters.cpu = (busy: UInt64(90 * step), total: UInt64(1000 + 100 * step))
            clock.advance(ActivityMonitor.interval)
            scheduler.runDue(at: clock.now)
        }
        #expect(answers.last == true)
        #expect(answers.filter { $0 }.count == 1) // reported once, not on every poll
    }

    @Test func networkActivityMonitorUsesByteRate() {
        let counters = FakeCounters()
        counters.network = 0
        let monitor = ActivityMonitor(
            kind: .network, threshold: ActivityThreshold(value: 1_000_000, sustain: 0, release: 0),
            counters: counters, clock: clock, scheduler: scheduler
        )
        var answers: [Bool] = []
        monitor.start { answers.append($0) }

        counters.network = 30_000_000 // 2 MB/s over 15 s
        clock.advance(ActivityMonitor.interval)
        scheduler.runDue(at: clock.now)
        #expect(answers.last == true)

        counters.network = 30_100_000 // ~7 KB/s
        clock.advance(ActivityMonitor.interval)
        scheduler.runDue(at: clock.now)
        #expect(answers.last == false)
    }

    @Test func diskActivityMonitorReadsWrites() {
        let counters = FakeCounters()
        counters.disk = 0
        let monitor = ActivityMonitor(
            kind: .disk, threshold: ActivityThreshold(value: 20_000_000, sustain: 0, release: 0),
            counters: counters, clock: clock, scheduler: scheduler
        )
        var answers: [Bool] = []
        monitor.start { answers.append($0) }

        counters.disk = 600_000_000 // 40 MB/s over 15 s
        clock.advance(ActivityMonitor.interval)
        scheduler.runDue(at: clock.now)
        #expect(answers.last == true)
    }

    @Test func missingCountersNeverReportBusy() {
        let counters = FakeCounters() // every reading nil
        let monitor = ActivityMonitor(
            kind: .cpu, threshold: ActivityThreshold(value: 1, sustain: 0, release: 0),
            counters: counters, clock: clock, scheduler: scheduler
        )
        var answers: [Bool] = []
        monitor.start { answers.append($0) }
        clock.advance(ActivityMonitor.interval)
        scheduler.runDue(at: clock.now)
        #expect(answers == [false])
    }

    @Test func reevaluateStartsAFreshBaselineAfterSleep() {
        let counters = FakeCounters()
        counters.network = 0
        let monitor = ActivityMonitor(
            kind: .network, threshold: ActivityThreshold(value: 1000, sustain: 0, release: 0),
            counters: counters, clock: clock, scheduler: scheduler
        )
        var answers: [Bool] = []
        monitor.start { answers.append($0) }

        // The Mac slept for an hour; the counter jumped, but that isn't a rate.
        counters.network = 500_000_000
        clock.advance(3600)
        monitor.reevaluate()
        scheduler.runDue(at: clock.now)
        #expect(answers.last == false)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test`
Expected: FAIL to compile with `cannot find 'ProcessRunningMonitor' in scope`.

- [ ] **Step 3: Write the polling monitors**

`Sources/EyesUpCore/Triggers/PollingMonitors.swift`:
```swift
import Foundation

/// True while any named command-line process is running. Polls only while its trigger is enabled.
@MainActor
public final class ProcessRunningMonitor: ConditionMonitor {
    public static let interval: TimeInterval = 10

    private let names: Set<String>
    private let lister: any ProcessLister
    private let clock: any WallClock
    private let scheduler: any TimerScheduling
    private var report: (@MainActor (Bool) -> Void)?
    private var task: (any ScheduledTask)?

    public init(names: [String], lister: any ProcessLister, clock: any WallClock, scheduler: any TimerScheduling) {
        self.names = Set(names.map { $0.lowercased() })
        self.lister = lister
        self.clock = clock
        self.scheduler = scheduler
    }

    public func start(_ report: @escaping @MainActor (Bool) -> Void) {
        self.report = report
        poll()
    }

    public func stop() {
        task?.cancel()
        task = nil
        report = nil
    }

    public func reevaluate() { poll() }

    private func poll() {
        task?.cancel()
        let running = Set(lister.runningProcessNames().map { $0.lowercased() })
        report?(!running.isDisjoint(with: names))
        task = scheduler.schedule(at: clock.now.addingTimeInterval(Self.interval)) { [weak self] in self?.poll() }
    }
}

/// True while the Mac is busy: CPU percent, network bytes/second or disk writes/second,
/// smoothed by an ActivityGate so brief spikes don't flap the hold.
@MainActor
public final class ActivityMonitor: ConditionMonitor {
    public enum Kind: Sendable { case cpu, network, disk }
    public static let interval: TimeInterval = 15

    private let kind: Kind
    private let counters: any SystemCounters
    private let clock: any WallClock
    private let scheduler: any TimerScheduling
    private var gate: ActivityGate
    private var rate = RateMeter()
    private var cpu = CPUMeter()
    private var report: (@MainActor (Bool) -> Void)?
    private var task: (any ScheduledTask)?

    public init(
        kind: Kind,
        threshold: ActivityThreshold,
        counters: any SystemCounters,
        clock: any WallClock,
        scheduler: any TimerScheduling
    ) {
        self.kind = kind
        self.counters = counters
        self.clock = clock
        self.scheduler = scheduler
        gate = ActivityGate(threshold: threshold)
    }

    public func start(_ report: @escaping @MainActor (Bool) -> Void) {
        self.report = report
        report(gate.isOn) // the first sample only sets a baseline
        poll()
    }

    public func stop() {
        task?.cancel()
        task = nil
        report = nil
    }

    /// Counters jump while the Mac sleeps, so start a fresh baseline instead of reading a huge rate.
    public func reevaluate() {
        rate = RateMeter()
        cpu = CPUMeter()
        poll()
    }

    private func poll() {
        task?.cancel()
        if let value = currentValue() {
            report?(gate.update(value: value, at: clock.now))
        }
        task = scheduler.schedule(at: clock.now.addingTimeInterval(Self.interval)) { [weak self] in self?.poll() }
    }

    private func currentValue() -> Double? {
        switch kind {
        case .cpu:
            guard let ticks = counters.cpuTicks() else { return nil }
            return cpu.percent(busy: ticks.busy, total: ticks.total)
        case .network:
            guard let bytes = counters.networkBytes() else { return nil }
            return rate.rate(for: bytes, at: clock.now)
        case .disk:
            guard let bytes = counters.diskBytesWritten() else { return nil }
            return rate.rate(for: bytes, at: clock.now)
        }
    }
}
```

The first `poll()` sets the baseline: `RateMeter`/`CPUMeter` return nil for a single sample, so nothing is reported until the second poll.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `make test`
Expected: all 7 `PollingMonitorTests` pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/EyesUpCore/Triggers/PollingMonitors.swift Tests/EyesUpCoreTests/PollingMonitorTests.swift
git commit -m "feat(core): add process-running and activity condition monitors" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 8: Live system sources and the monitor factory

**Files:**
- Create: `Sources/EyesUpCore/System/LiveSystemSources.swift`, `Sources/EyesUpCore/System/LiveConditionMonitorFactory.swift`, `Tests/EyesUpCoreTests/LiveSystemSourcesTests.swift`

**Interfaces:**
- Consumes: the protocols from Task 6, the monitors from Tasks 6–7.
- Produces:
  - `LiveSystemCounters()`, `LiveProcessLister()`, `LiveDisplayInventory()`, `LivePowerSourceInfo()`, `LiveThermalMonitor()`
  - `LiveConditionMonitorFactory(workspace:clock:scheduler:counters:lister:displays:power:)` conforming to `ConditionMonitorFactory`

All of these were verified to work without admin rights on the target Mac (M3 Ultra, macOS 26.7).

- [ ] **Step 1: Write the failing tests**

`Tests/EyesUpCoreTests/LiveSystemSourcesTests.swift`:
```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test`
Expected: FAIL to compile with `cannot find 'LiveSystemCounters' in scope`.

- [ ] **Step 3: Write the live sources**

`Sources/EyesUpCore/System/LiveSystemSources.swift`:
```swift
import CoreGraphics
import Darwin
import Foundation
import IOKit
import IOKit.ps

/// Carries a main-actor handler across a C callback boundary.
private final class CallbackBox: @unchecked Sendable {
    let handler: @MainActor () -> Void

    init(_ handler: @escaping @MainActor () -> Void) {
        self.handler = handler
    }

    func fire() {
        DispatchQueue.main.async { MainActor.assumeIsolated { self.handler() } }
    }
}

// One shared function pointer per API: CoreGraphics only removes a callback that is
// *identical* to the one registered, and two identical closures are two different pointers.
private let displayCallback: CGDisplayReconfigurationCallBack = { _, flags, context in
    guard !flags.contains(.beginConfigurationFlag), let context else { return }
    Unmanaged<CallbackBox>.fromOpaque(context).takeUnretainedValue().fire()
}

private let powerCallback: IOPowerSourceCallbackType = { context in
    guard let context else { return }
    Unmanaged<CallbackBox>.fromOpaque(context).takeUnretainedValue().fire()
}

/// Kernel counters for the activity triggers. Everything here works without admin rights.
public struct LiveSystemCounters: SystemCounters {
    public init() {}

    public func cpuTicks() -> (busy: UInt64, total: UInt64)? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let ticks = info.cpu_ticks
        let user = UInt64(ticks.0), system = UInt64(ticks.1), idle = UInt64(ticks.2), nice = UInt64(ticks.3)
        return (busy: user + system + nice, total: user + system + idle + nice)
    }

    /// Bytes in + out across every non-loopback interface, from the 64-bit interface list.
    public func networkBytes() -> UInt64? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else { return nil }

        var total: UInt64 = 0
        var offset = 0
        buffer.withUnsafeBytes { raw in
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                guard header.ifm_msglen > 0 else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2 {
                    let extended = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    if extended.ifm_data.ifi_type != UInt8(IFT_LOOP) {
                        total += extended.ifm_data.ifi_ibytes + extended.ifm_data.ifi_obytes
                    }
                }
                offset += Int(header.ifm_msglen)
            }
        }
        return total
    }

    public func diskBytesWritten() -> UInt64? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var total: UInt64 = 0
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let statistics = IORegistryEntryCreateCFProperty(service, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any],
                let written = statistics["Bytes (Write)"] as? NSNumber else { continue }
            total += written.uint64Value
        }
        return total
    }
}

/// Process names visible to this user (libproc).
public struct LiveProcessLister: ProcessLister {
    public init() {}

    public func runningProcessNames() -> Set<String> {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let written = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard written > 0 else { return [] }

        var names: Set<String> = []
        for pid in pids.prefix(Int(written)) where pid > 0 {
            var buffer = [CChar](repeating: 0, count: 256)
            let length = proc_name(pid, &buffer, UInt32(buffer.count))
            guard length > 0 else { continue }
            names.insert(String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self))
        }
        return names
    }
}

@MainActor
public final class LiveDisplayInventory: DisplayInventory {
    private var box: CallbackBox?

    public init() {}

    public func connectedDisplays() -> [DisplayMatch] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).map { id in
            DisplayMatch(
                vendor: CGDisplayVendorNumber(id),
                model: CGDisplayModelNumber(id),
                serial: CGDisplaySerialNumber(id),
                name: "Display \(CGDisplayModelNumber(id))"
            )
        }
    }

    public func observeChanges(_ handler: @escaping @MainActor () -> Void) -> any ScheduledTask {
        let box = CallbackBox(handler)
        self.box = box
        CGDisplayRegisterReconfigurationCallback(displayCallback, Unmanaged.passUnretained(box).toOpaque())
        return CallbackObservation { [weak self] in
            CGDisplayRemoveReconfigurationCallback(displayCallback, Unmanaged.passUnretained(box).toOpaque())
            self?.box = nil
        }
    }
}

@MainActor
public final class LivePowerSourceInfo: PowerSourceInfo {
    private var box: CallbackBox?
    private var source: CFRunLoopSource?

    public init() {}

    public func isOnACPower() -> Bool {
        (IOPSGetProvidingPowerSourceType(nil)?.takeUnretainedValue() as String?) == kIOPMACPowerKey
    }

    public func observeChanges(_ handler: @escaping @MainActor () -> Void) -> any ScheduledTask {
        let box = CallbackBox(handler)
        self.box = box
        let source = IOPSNotificationCreateRunLoopSource(powerCallback, Unmanaged.passUnretained(box).toOpaque())?
            .takeRetainedValue()
        self.source = source
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode) }
        return CallbackObservation { [weak self] in
            if let source = self?.source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode) }
            self?.source = nil
            self?.box = nil
        }
    }
}

@MainActor
public final class LiveThermalMonitor: ThermalMonitoring {
    public init() {}

    public func currentLevel() -> ThermalLevel {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .nominal
        }
    }

    public func observeChanges(_ handler: @escaping @MainActor () -> Void) -> any ScheduledTask {
        let token = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { handler() }
        }
        return CallbackObservation { NotificationCenter.default.removeObserver(token) }
    }
}

/// A cancellable registration, so observers look like every other ScheduledTask.
@MainActor
final class CallbackObservation: ScheduledTask {
    private var onCancel: (@MainActor () -> Void)?

    init(_ onCancel: @escaping @MainActor () -> Void) {
        self.onCancel = onCancel
    }

    func cancel() {
        onCancel?()
        onCancel = nil
    }
}
```

`Sources/EyesUpCore/System/LiveConditionMonitorFactory.swift`:
```swift
import Foundation

/// Builds the real monitor for each condition. The workspace comes from the app layer (NSWorkspace).
@MainActor
public final class LiveConditionMonitorFactory: ConditionMonitorFactory {
    private let workspace: any WorkspaceEvents
    private let clock: any WallClock
    private let scheduler: any TimerScheduling
    private let counters: any SystemCounters
    private let lister: any ProcessLister
    private let displays: any DisplayInventory
    private let power: any PowerSourceInfo

    public init(
        workspace: any WorkspaceEvents,
        clock: any WallClock = SystemClock(),
        scheduler: any TimerScheduling,
        counters: any SystemCounters = LiveSystemCounters(),
        lister: any ProcessLister = LiveProcessLister(),
        displays: any DisplayInventory = LiveDisplayInventory(),
        power: any PowerSourceInfo = LivePowerSourceInfo()
    ) {
        self.workspace = workspace
        self.clock = clock
        self.scheduler = scheduler
        self.counters = counters
        self.lister = lister
        self.displays = displays
        self.power = power
    }

    public func makeMonitor(for condition: TriggerCondition) -> any ConditionMonitor {
        switch condition {
        case .appRunning(let bundleIDs):
            AppRunningMonitor(bundleIDs: bundleIDs, workspace: workspace)
        case .processRunning(let names):
            ProcessRunningMonitor(names: names, lister: lister, clock: clock, scheduler: scheduler)
        case .schedule(let schedule):
            ScheduleMonitor(schedule: schedule, clock: clock, scheduler: scheduler)
        case .cpuBusy(let threshold):
            ActivityMonitor(kind: .cpu, threshold: threshold, counters: counters, clock: clock, scheduler: scheduler)
        case .networkBusy(let threshold):
            ActivityMonitor(kind: .network, threshold: threshold, counters: counters, clock: clock, scheduler: scheduler)
        case .diskBusy(let threshold):
            ActivityMonitor(kind: .disk, threshold: threshold, counters: counters, clock: clock, scheduler: scheduler)
        case .displayConnected(let match):
            DisplayConnectedMonitor(match: match, displays: displays)
        case .onACPower:
            PowerSourceMonitor(power: power)
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `make test`
Expected: the 4 non-integration `LiveSystemSourcesTests` pass; the display/power test is skipped.
Run: `make test-integration`
Expected: all 5 pass, including displays and AC power.

- [ ] **Step 5: Commit**

```bash
git add Sources/EyesUpCore/System Tests/EyesUpCoreTests/LiveSystemSourcesTests.swift
git commit -m "feat(core): add live system counters, process lister, displays, power and thermal sources" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 9: Settings storage

**Files:**
- Create: `Sources/EyesUpCore/Store/AppSettings.swift`, `Tests/EyesUpCoreTests/SettingsTests.swift`

**Interfaces:**
- Consumes: `JSONFileStore`, `TriggerPause` (Task 5).
- Produces:
  - `struct AppSettings { safetyCapHours: Double?; thermalAutoRelease: Bool; automationEnabled: Bool; triggerPause: TriggerPause; func validated() -> AppSettings; static minSafetyCapHours = 1; static maxSafetyCapHours = 168 }`
  - `@MainActor @Observable final class SettingsController { settings; onChange; init(store:); load(); update(_:) }`

- [ ] **Step 1: Write the failing tests**

`Tests/EyesUpCoreTests/SettingsTests.swift`:
```swift
import Foundation
import Testing
@testable import EyesUpCore

@Suite @MainActor struct SettingsTests {
    func tempStore() -> JSONFileStore<AppSettings> {
        JSONFileStore(
            url: FileManager.default.temporaryDirectory.appendingPathComponent("EyesUpTests-\(UUID().uuidString)/settings.json"),
            schemaVersion: 1
        )
    }

    @Test func defaultsAreSafe() {
        let settings = AppSettings()
        #expect(settings.safetyCapHours == nil)
        #expect(settings.thermalAutoRelease)
        #expect(!settings.automationEnabled) // the automation link is off until asked for
        #expect(settings.triggerPause == .none)
    }

    @Test func missingKeysFallBackToDefaults() throws {
        let partial = Data(#"{"automationEnabled":true}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: partial)
        #expect(settings.automationEnabled)
        #expect(settings.thermalAutoRelease)
        #expect(settings.safetyCapHours == nil)
    }

    @Test func validationClampsOutOfRangeValues() {
        #expect(AppSettings(safetyCapHours: 0.5).validated().safetyCapHours == nil)
        #expect(AppSettings(safetyCapHours: 1000).validated().safetyCapHours == nil)
        #expect(AppSettings(safetyCapHours: .nan).validated().safetyCapHours == nil)
        #expect(AppSettings(safetyCapHours: 8).validated().safetyCapHours == 8)
        let farFuture = AppSettings(triggerPause: .until(Date().addingTimeInterval(40 * 86_400)))
        #expect(farFuture.validated().triggerPause == .none)
        #expect(AppSettings(triggerPause: .untilResumed).validated().triggerPause == .untilResumed)
    }

    @Test func updatePersistsAndNotifies() throws {
        let store = tempStore()
        let controller = SettingsController(store: store)
        var seen: [AppSettings] = []
        controller.onChange = { seen.append($0) }

        controller.update { $0.safetyCapHours = 12 }
        #expect(controller.settings.safetyCapHours == 12)
        #expect(seen.last?.safetyCapHours == 12)

        let reloaded = SettingsController(store: store)
        reloaded.load()
        #expect(reloaded.settings.safetyCapHours == 12)
    }

    @Test func updateValidatesBeforeSaving() {
        let controller = SettingsController(store: tempStore())
        controller.update { $0.safetyCapHours = 0.1 }
        #expect(controller.settings.safetyCapHours == nil)
    }

    @Test func corruptSettingsFallBackToDefaultsWithANotice() throws {
        let store = tempStore()
        try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.url)
        let controller = SettingsController(store: store)
        controller.load()
        #expect(controller.settings == AppSettings())
        #expect(controller.storeNotice != nil)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test`
Expected: FAIL to compile with `cannot find 'AppSettings' in scope`.

- [ ] **Step 3: Implement settings**

`Sources/EyesUpCore/Store/AppSettings.swift`:
```swift
import Foundation
import Observation

/// User settings (spec §8). Decoding tolerates missing keys so later versions can add fields
/// without a schema bump, and out-of-range values fall back to their defaults.
public struct AppSettings: Codable, Equatable, Sendable {
    public static let minSafetyCapHours = 1.0
    public static let maxSafetyCapHours = 168.0
    /// Longest a "pause until" may sit in the future before it's treated as stale.
    public static let maxPauseDays = 30.0

    public var safetyCapHours: Double?
    public var thermalAutoRelease: Bool
    public var automationEnabled: Bool
    public var triggerPause: TriggerPause

    public init(
        safetyCapHours: Double? = nil,
        thermalAutoRelease: Bool = true,
        automationEnabled: Bool = false,
        triggerPause: TriggerPause = .none
    ) {
        self.safetyCapHours = safetyCapHours
        self.thermalAutoRelease = thermalAutoRelease
        self.automationEnabled = automationEnabled
        self.triggerPause = triggerPause
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        safetyCapHours = try container.decodeIfPresent(Double.self, forKey: .safetyCapHours)
        thermalAutoRelease = try container.decodeIfPresent(Bool.self, forKey: .thermalAutoRelease) ?? true
        automationEnabled = try container.decodeIfPresent(Bool.self, forKey: .automationEnabled) ?? false
        triggerPause = try container.decodeIfPresent(TriggerPause.self, forKey: .triggerPause) ?? .none
    }

    public func validated(now: Date = Date()) -> AppSettings {
        var settings = self
        if let hours = settings.safetyCapHours {
            let usable = hours.isFinite && hours >= Self.minSafetyCapHours && hours <= Self.maxSafetyCapHours
            settings.safetyCapHours = usable ? hours : nil
        }
        if case .until(let date) = settings.triggerPause,
           date.timeIntervalSince(now) > Self.maxPauseDays * 86_400 {
            settings.triggerPause = .none
        }
        return settings
    }
}

/// Holds the settings, saves every change, and tells whoever cares.
@MainActor
@Observable
public final class SettingsController {
    public private(set) var settings: AppSettings
    public private(set) var storeNotice: String?
    @ObservationIgnored public var onChange: ((AppSettings) -> Void)?

    @ObservationIgnored private let store: JSONFileStore<AppSettings>?

    public init(store: JSONFileStore<AppSettings>?, settings: AppSettings = AppSettings()) {
        self.store = store
        self.settings = settings
    }

    public func load() {
        guard let store else { return }
        switch store.load() {
        case .missing:
            break
        case .loaded(let saved):
            settings = saved.validated()
        case .corrupt:
            storeNotice = "Settings couldn't be read, so they were reset to their defaults."
        }
        onChange?(settings)
    }

    public func update(_ change: (inout AppSettings) -> Void) {
        var updated = settings
        change(&updated)
        settings = updated.validated()
        persist()
        onChange?(settings)
    }

    private func persist() {
        guard let store else { return }
        do {
            try store.save(settings)
        } catch {
            storeNotice = "Couldn't save settings: \(error.localizedDescription)"
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `make test`
Expected: all 6 `SettingsTests` pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/EyesUpCore/Store/AppSettings.swift Tests/EyesUpCoreTests/SettingsTests.swift
git commit -m "feat(core): add app settings with lenient decoding and validation" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 10: Automation link (`eyesup://`)

**Files:**
- Create: `Sources/EyesUpCore/Automation/AutomationCommand.swift`, `Tests/EyesUpCoreTests/AutomationTests.swift`
- Modify: `Sources/EyesUpCore/AwakeController.swift` (add `apply(_:)`)
- Modify: `Tests/EyesUpCoreTests/AwakeControllerTests.swift`

**Interfaces:**
- Consumes: `DurationParser`, `ParsedDuration`, `AwakeController`, `TimeFormatting`.
- Produces:
  - `enum AutomationCommand { start(duration: ParsedDuration, display: Bool), stop, extend(by: TimeInterval) }`
  - `enum AutomationError: Error { disabled, badScheme, unknownCommand, badParameter, missingParameter }` with `message`
  - `enum AutomationParser { static let scheme = "eyesup"; static let maxDuration: TimeInterval = 86400; static func parse(_ url: URL, cap: TimeInterval?) throws -> AutomationCommand }`
  - `AwakeController.apply(_ command: AutomationCommand) throws -> String` (returns the message to show)

- [ ] **Step 1: Write the failing tests**

`Tests/EyesUpCoreTests/AutomationTests.swift`:
```swift
import Foundation
import Testing
@testable import EyesUpCore

@Suite struct AutomationTests {
    private func parse(_ string: String, cap: TimeInterval? = nil) throws -> AutomationCommand {
        try AutomationParser.parse(#require(URL(string: string)), cap: cap)
    }

    @Test func acceptsTheThreeCommands() throws {
        #expect(try parse("eyesup://start?for=2h") == .start(duration: .finite(7200), display: false))
        #expect(try parse("eyesup://start?for=90m&display=true") == .start(duration: .finite(5400), display: true))
        #expect(try parse("eyesup://start?for=inf") == .start(duration: .infinite, display: false))
        #expect(try parse("eyesup://stop") == .stop)
        #expect(try parse("eyesup://extend?by=30m") == .extend(by: 1800))
        #expect(try parse("EYESUP://START?for=1h") == .start(duration: .finite(3600), display: false))
    }

    @Test(arguments: [
        "eyesup://start",                    // missing for=
        "eyesup://start?for=",               // empty
        "eyesup://start?for=25h",            // over the 24h link cap
        "eyesup://start?for=1h&for=2h",      // duplicate key
        "eyesup://start?for=1h&secret=1",    // unexpected key
        "eyesup://start?for=1%20h",          // whitespace
        "eyesup://start?for=%D9%A3h",        // non-ASCII digits
        "eyesup://start?for=1h&display=maybe",
        "eyesup://launch?for=1h",            // unknown command
        "eyesup://stop?all=true",            // stop takes no parameters
        "eyesup://extend",                   // missing by=
        "eyesup://extend?by=inf",            // can't extend by forever
        "https://start?for=1h",              // wrong scheme
        "eyesup://start?for=0m",
        "eyesup://start?for=-1h",
    ])
    func rejectsMalformedLinks(string: String) throws {
        let url = try #require(URL(string: string))
        #expect(throws: (any Error).self) { try AutomationParser.parse(url, cap: nil) }
    }

    @Test func honoursASafetyCapLowerThanTheLinkCap() throws {
        #expect(throws: AutomationError.badParameter) { try parse("eyesup://start?for=6h", cap: 3600) }
        #expect(try parse("eyesup://start?for=30m", cap: 3600) == .start(duration: .finite(1800), display: false))
    }
}
```

Append inside `AwakeControllerTests` (before its closing brace):
```swift
    // MARK: Automation

    @Test func automationStartCreatesItsOwnHold() throws {
        let controller = makeController()
        _ = try controller.apply(.start(duration: .finite(3600), display: true))
        #expect(controller.holds.count == 1)
        #expect(controller.holds.first?.source == .automation)
        #expect(provider.liveKinds == [.preventIdleSystemSleep, .preventDisplaySleep])

        _ = try controller.apply(.start(duration: .finite(1800), display: false))
        #expect(controller.holds.count == 1) // replaces its previous session
        #expect(controller.awakeUntil == referenceDate.addingTimeInterval(1800))
    }

    @Test func stopOnlyEndsAutomationHolds() throws {
        let controller = makeController()
        try controller.startTimer(duration: 3600, policy: .system)
        _ = try controller.apply(.start(duration: .infinite, display: false))
        _ = try controller.apply(.stop)
        #expect(controller.holds.map(\.source) == [.manual])
        #expect(controller.isAwake)
    }

    @Test func automationExtendAddsToItsOwnHoldOrStartsOne() throws {
        let controller = makeController()
        _ = try controller.apply(.start(duration: .finite(3600), display: false))
        _ = try controller.apply(.extend(by: 1800))
        #expect(controller.awakeUntil == referenceDate.addingTimeInterval(5400))

        let fresh = makeController()
        _ = try fresh.apply(.extend(by: 1800))
        #expect(fresh.holds.count == 1)
        #expect(fresh.holds.first?.source == .automation)
    }

    @Test func automationRejectsAbsurdDurations() {
        let controller = makeController()
        #expect(throws: AwakeError.invalidDuration) { try controller.apply(.extend(by: 0)) }
        #expect(throws: AwakeError.invalidDuration) { try controller.apply(.start(duration: .finite(1e12), display: false)) }
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test`
Expected: FAIL to compile with `cannot find 'AutomationParser' in scope`.

- [ ] **Step 3: Write the parser**

`Sources/EyesUpCore/Automation/AutomationCommand.swift`:
```swift
import Foundation

/// The only things a link may ask for (spec §5.1). It can never quit a process or change settings.
public enum AutomationCommand: Equatable, Sendable {
    case start(duration: ParsedDuration, display: Bool)
    case stop
    case extend(by: TimeInterval)
}

public enum AutomationError: Error, Equatable, Sendable {
    case disabled
    case badScheme
    case unknownCommand
    case badParameter
    case missingParameter

    public var message: String {
        switch self {
        case .disabled: "Automation links are switched off in Settings."
        case .badScheme: "That isn't an eyesup:// link."
        case .unknownCommand: "Use eyesup://start, eyesup://stop or eyesup://extend."
        case .badParameter: "A value in that link isn't allowed."
        case .missingParameter: "That link is missing a duration."
        }
    }
}

public enum AutomationParser {
    public static let scheme = "eyesup"
    /// The longest any link may ask for, whatever the safety cap says.
    public static let maxDuration: TimeInterval = 24 * 3600
    private static let maxQueryItems = 4

    public static func parse(_ url: URL, cap: TimeInterval? = nil) throws -> AutomationCommand {
        guard url.scheme?.lowercased() == scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw AutomationError.badScheme
        }
        let command = (components.host ?? "").lowercased()
        let items = components.queryItems ?? []
        guard items.count <= maxQueryItems else { throw AutomationError.badParameter }

        var values: [String: String] = [:]
        for item in items {
            let key = item.name.lowercased()
            guard values[key] == nil else { throw AutomationError.badParameter } // duplicate keys
            values[key] = item.value ?? ""
        }
        let limit = min(maxDuration, cap ?? maxDuration)

        switch command {
        case "start":
            try allow(keys: ["for", "display"], in: values)
            guard let raw = values["for"], !raw.isEmpty else { throw AutomationError.missingParameter }
            return .start(duration: try duration(raw, limit: limit), display: try flag(values["display"]))
        case "stop":
            try allow(keys: [], in: values)
            return .stop
        case "extend":
            try allow(keys: ["by"], in: values)
            guard let raw = values["by"], !raw.isEmpty else { throw AutomationError.missingParameter }
            guard case .finite(let seconds) = try duration(raw, limit: limit) else { throw AutomationError.badParameter }
            return .extend(by: seconds)
        default:
            throw AutomationError.unknownCommand
        }
    }

    private static func allow(keys: Set<String>, in values: [String: String]) throws {
        guard Set(values.keys).isSubset(of: keys) else { throw AutomationError.badParameter }
    }

    private static func duration(_ raw: String, limit: TimeInterval) throws -> ParsedDuration {
        guard raw.count <= 9, !raw.contains(where: \.isWhitespace),
              let parsed = DurationParser.parse(raw) else { throw AutomationError.badParameter }
        if case .finite(let seconds) = parsed, seconds > limit { throw AutomationError.badParameter }
        return parsed
    }

    private static func flag(_ raw: String?) throws -> Bool {
        switch raw?.lowercased() {
        case nil, "": false
        case "1", "true", "yes": true
        case "0", "false", "no": false
        default: throw AutomationError.badParameter
        }
    }
}
```

- [ ] **Step 4: Let the controller run a command**

Add to `Sources/EyesUpCore/AwakeController.swift`, right above `// MARK: Safety`:
```swift
    // MARK: Automation (spec §5.1)

    /// Runs an already-validated link command. Automation only ever touches its own holds,
    /// so a link can never cancel a session you started by hand.
    @discardableResult
    public func apply(_ command: AutomationCommand) throws -> String {
        switch command {
        case .start(let duration, let display):
            let policy: SleepPolicy = display ? [.system, .display] : .system
            let now = clock.now
            switch duration {
            case .finite(let seconds):
                guard seconds > 0, seconds <= Self.maxManualDuration else { throw AwakeError.invalidDuration }
                holds.removeAll { $0.source == .automation }
                holds.append(Hold(source: .automation, label: "Automation \(TimeFormatting.duration(seconds))",
                                  policy: policy, end: .deadline(now.addingTimeInterval(seconds)), createdAt: now))
                commit()
                return "Automation: keeping your Mac awake for \(TimeFormatting.duration(seconds))."
            case .infinite:
                holds.removeAll { $0.source == .automation }
                holds.append(Hold(source: .automation, label: "Automation (no end time)",
                                  policy: policy, end: .indefinite, createdAt: now))
                commit()
                return "Automation: keeping your Mac awake with no end time."
            }
        case .stop:
            remove(ids: Set(holds.filter { $0.source == .automation }.map(\.id)))
            return "Automation: stopped its keep-awake session."
        case .extend(let seconds):
            guard seconds > 0, seconds <= Self.maxManualDuration else { throw AwakeError.invalidDuration }
            var extended = false
            for index in holds.indices where holds[index].source == .automation {
                guard case .deadline(let date) = holds[index].end else { continue }
                let newDate = date.addingTimeInterval(seconds)
                holds[index].end = .deadline(newDate)
                holds[index].label = "Automation until " + newDate.formatted(date: .omitted, time: .shortened)
                extended = true
            }
            if extended {
                commit()
            } else {
                return try apply(.start(duration: .finite(seconds), display: false))
            }
            return "Automation: extended by \(TimeFormatting.duration(seconds))."
        }
    }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `make test`
Expected: all `AutomationTests` (including the 15 rejection cases) and the 4 new controller tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/EyesUpCore Tests/EyesUpCoreTests
git commit -m "feat(core): add strictly validated eyesup:// automation commands" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 11: Safety guard (thermal release) and settings wiring

**Files:**
- Create: `Sources/EyesUpCore/Safety/SafetyGuard.swift`, `Tests/EyesUpCoreTests/SafetyGuardTests.swift`

**Interfaces:**
- Consumes: `AwakeController`, `ThermalMonitoring`, `AppSettings`, `TriggerEngine`.
- Produces:
  - `@MainActor final class SafetyGuard { init(controller:thermal:); var thermalAutoRelease: Bool; var onThermalRelease: (() -> Void)?; func start(); func stop(); func evaluate() }`
  - `@MainActor enum SettingsApplier { static func apply(_ settings: AppSettings, controller:engine:safety:) }`

- [ ] **Step 1: Write the failing tests**

`Tests/EyesUpCoreTests/SafetyGuardTests.swift`:
```swift
import Foundation
import Testing
@testable import EyesUpCore

@Suite @MainActor struct SafetyGuardTests {
    let provider = FakePowerAssertions()
    let clock = FakeClock()
    let scheduler = FakeScheduler()
    let thermal = FakeThermal()

    func makeController() -> AwakeController {
        AwakeController(provider: provider, clock: clock, scheduler: scheduler,
                        exitWatcher: FakeExitWatcher(), inspector: FakeInspector(), holdStore: nil)
    }

    @Test func criticalThermalStateReleasesEverything() {
        let controller = makeController()
        controller.startIndefinite(policy: .system)
        controller.beginTriggerHold(triggerID: UUID(), label: "Claude running", policy: .system)
        let safety = SafetyGuard(controller: controller, thermal: thermal)
        var notified = false
        safety.onThermalRelease = { notified = true }
        safety.start()

        thermal.change(to: .critical)
        #expect(controller.holds.isEmpty)
        #expect(provider.live.isEmpty)
        #expect(notified)
    }

    @Test func lesserHeatIsLeftAlone() {
        let controller = makeController()
        controller.startIndefinite(policy: .system)
        let safety = SafetyGuard(controller: controller, thermal: thermal)
        safety.start()

        thermal.change(to: .serious)
        #expect(controller.isAwake)
    }

    @Test func switchingTheGuardOffLeavesHoldsAlone() {
        let controller = makeController()
        controller.startIndefinite(policy: .system)
        let safety = SafetyGuard(controller: controller, thermal: thermal)
        safety.thermalAutoRelease = false
        safety.start()

        thermal.change(to: .critical)
        #expect(controller.isAwake)
    }

    @Test func anAlreadyCriticalMacIsHandledAtStart() {
        let controller = makeController()
        controller.startIndefinite(policy: .system)
        thermal.level = .critical
        let safety = SafetyGuard(controller: controller, thermal: thermal)
        safety.start()
        #expect(controller.holds.isEmpty)
    }

    @Test func noNotificationWhenNothingWasHeld() {
        let controller = makeController()
        let safety = SafetyGuard(controller: controller, thermal: thermal)
        var notified = false
        safety.onThermalRelease = { notified = true }
        safety.start()
        thermal.change(to: .critical)
        #expect(!notified)
    }

    @Test func settingsApplierPushesEverySetting() {
        let controller = makeController()
        let engine = TriggerEngine(controller: controller, factory: FakeMonitorFactory(),
                                   clock: clock, scheduler: scheduler, store: nil)
        let safety = SafetyGuard(controller: controller, thermal: thermal)

        SettingsApplier.apply(
            AppSettings(safetyCapHours: 4, thermalAutoRelease: false, automationEnabled: true, triggerPause: .untilResumed),
            controller: controller, engine: engine, safety: safety
        )
        #expect(controller.safetyCap == 4 * 3600)
        #expect(!safety.thermalAutoRelease)
        #expect(engine.pause == .untilResumed)

        SettingsApplier.apply(AppSettings(), controller: controller, engine: engine, safety: safety)
        #expect(controller.safetyCap == nil)
        #expect(safety.thermalAutoRelease)
        #expect(engine.pause == .none)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test`
Expected: FAIL to compile with `cannot find 'SafetyGuard' in scope`.

- [ ] **Step 3: Implement the guard**

`Sources/EyesUpCore/Safety/SafetyGuard.swift`:
```swift
import Foundation

/// Spec §4.5: when the Mac reaches a critical thermal state, stop keeping it awake.
@MainActor
public final class SafetyGuard {
    public var thermalAutoRelease = true
    public var onThermalRelease: (() -> Void)?

    private let controller: AwakeController
    private let thermal: any ThermalMonitoring
    private var observation: (any ScheduledTask)?

    public init(controller: AwakeController, thermal: any ThermalMonitoring) {
        self.controller = controller
        self.thermal = thermal
    }

    public func start() {
        observation = thermal.observeChanges { [weak self] in self?.evaluate() }
        evaluate()
    }

    public func stop() {
        observation?.cancel()
        observation = nil
    }

    public func evaluate() {
        guard thermalAutoRelease, thermal.currentLevel() == .critical, controller.isAwake else { return }
        controller.releaseAllForSafety()
        onThermalRelease?()
    }
}

/// Pushes saved settings into the pieces that act on them.
@MainActor
public enum SettingsApplier {
    public static func apply(
        _ settings: AppSettings,
        controller: AwakeController,
        engine: TriggerEngine,
        safety: SafetyGuard
    ) {
        controller.setSafetyCap(settings.safetyCapHours.map { $0 * 3600 })
        safety.thermalAutoRelease = settings.thermalAutoRelease
        if engine.pause != settings.triggerPause { engine.setPause(settings.triggerPause) }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `make test`
Expected: all 6 `SafetyGuardTests` pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/EyesUpCore/Safety Tests/EyesUpCoreTests/SafetyGuardTests.swift
git commit -m "feat(core): release holds on critical heat and apply saved safety settings" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 12: App wiring (workspace source, environment, notifications)

**Files:**
- Create: `Sources/EyesUpApp/System/LiveWorkspaceEvents.swift`
- Modify (replace entirely): `Sources/EyesUpApp/AppEnvironment.swift`
- Modify: `Sources/EyesUpApp/Notifications/HeadsUpNotifier.swift` (add `postInfo(_:id:)`)
- Modify: `Sources/EyesUpApp/EyesUpGuardianApp.swift` (connect the new callbacks)

**Interfaces:**
- Consumes: `TriggerEngine`, `SettingsController`, `SafetyGuard`, `SettingsApplier`, `LiveConditionMonitorFactory`, `LiveThermalMonitor`.
- Produces:
  - `LiveWorkspaceEvents` (conforms to `WorkspaceEvents`, plus `runningApps() -> [(bundleID: String, name: String)]` for the editor's picker)
  - `AppEnvironment.engine`, `.settings`, `.safety`, `.workspace`, `.automationEnabled`
  - `HeadsUpNotifier.postInfo(_ body: String, id: String)`

- [ ] **Step 1: Write the workspace source**

`Sources/EyesUpApp/System/LiveWorkspaceEvents.swift`:
```swift
import AppKit
import EyesUpCore

/// NSWorkspace lives in AppKit, which EyesUpCore must not import, so the app supplies it.
@MainActor
final class LiveWorkspaceEvents: WorkspaceEvents {
    func runningBundleIDs() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    func observeChanges(_ handler: @escaping @MainActor () -> Void) -> any ScheduledTask {
        let center = NSWorkspace.shared.notificationCenter
        let forward: @Sendable (Notification) -> Void = { _ in MainActor.assumeIsolated { handler() } }
        let launched = center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification,
                                          object: nil, queue: .main, using: forward)
        let terminated = center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                                            object: nil, queue: .main, using: forward)
        return WorkspaceObservation {
            center.removeObserver(launched)
            center.removeObserver(terminated)
        }
    }

    /// Apps with a Dock icon, for the trigger editor's picker.
    func runningApps() -> [(bundleID: String, name: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in app.bundleIdentifier.map { (bundleID: $0, name: app.localizedName ?? $0) } }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

@MainActor
final class WorkspaceObservation: ScheduledTask {
    private var onCancel: (@MainActor () -> Void)?

    init(_ onCancel: @escaping @MainActor () -> Void) { self.onCancel = onCancel }

    func cancel() {
        onCancel?()
        onCancel = nil
    }
}
```

- [ ] **Step 2: Rebuild the environment**

`Sources/EyesUpApp/AppEnvironment.swift` (replaces the Plan 1 version):
```swift
import AppKit
import EyesUpCore

enum Defaults {
    static let presets: [TimeInterval] = [900, 3600, 7200, 14400]
    static let headsUpLead: TimeInterval = 300
    static let extendStep: TimeInterval = 1800
}

/// Builds the real dependencies and connects system events to the controller and trigger engine.
@MainActor
final class AppEnvironment {
    let controller: AwakeController
    let engine: TriggerEngine
    let settings: SettingsController
    let safety: SafetyGuard
    let workspace: LiveWorkspaceEvents

    private var observers: [NSObjectProtocol] = []

    init() {
        let inspector = LibprocInspector()
        let scheduler = DispatchTimerScheduler()
        let directory = StorageLocation.directory
        let workspace = LiveWorkspaceEvents()

        controller = AwakeController(
            provider: IOKitPowerAssertions(),
            scheduler: scheduler,
            exitWatcher: KqueueExitWatcher(inspector: inspector),
            inspector: inspector,
            holdStore: JSONFileStore(url: directory.appendingPathComponent("holds.json"), schemaVersion: 1),
            headsUpLead: Defaults.headsUpLead
        )
        engine = TriggerEngine(
            controller: controller,
            factory: LiveConditionMonitorFactory(workspace: workspace, scheduler: scheduler),
            scheduler: scheduler,
            store: JSONFileStore(url: directory.appendingPathComponent("triggers.json"), schemaVersion: 1)
        )
        settings = SettingsController(
            store: JSONFileStore(url: directory.appendingPathComponent("settings.json"), schemaVersion: 1)
        )
        safety = SafetyGuard(controller: controller, thermal: LiveThermalMonitor())
        self.workspace = workspace
    }

    func start() {
        settings.onChange = { [weak self] settings in
            guard let self else { return }
            SettingsApplier.apply(settings, controller: controller, engine: engine, safety: safety)
        }
        controller.restore()
        engine.load()      // triggers first, so settings can pause them
        settings.load()
        safety.start()

        let refresh: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated {
                self?.controller.refresh()
                self?.engine.refresh()
            }
        }
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observers.append(workspaceCenter.addObserver(forName: NSWorkspace.didWakeNotification,
                                                     object: nil, queue: .main, using: refresh))
        observers.append(NotificationCenter.default.addObserver(forName: .NSSystemClockDidChange,
                                                                object: nil, queue: .main, using: refresh))
        observers.append(NotificationCenter.default.addObserver(forName: .NSSystemTimeZoneDidChange,
                                                                object: nil, queue: .main, using: refresh))
    }

    /// Spec §5.1: links do nothing unless the user switched them on.
    var automationEnabled: Bool { settings.settings.automationEnabled }

    func shutdown() {
        engine.shutdown()
        safety.stop()
        controller.shutdown()
    }
}
```

- [ ] **Step 3: Let the notifier post plain messages**

In `Sources/EyesUpApp/Notifications/HeadsUpNotifier.swift`, add after `private func post(end: Date)`:
```swift
    /// A short informational banner: trigger changes, safety releases, automation results.
    func postInfo(_ body: String, id: String) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = "EyesUpGuardian"
        content.body = body
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) { _ in }
    }
```

- [ ] **Step 4: Connect the callbacks**

In `Sources/EyesUpApp/EyesUpGuardianApp.swift`, replace the line
```swift
        headsUp = HeadsUpNotifier(controller: environment.controller)
```
with:
```swift
        let notifier = HeadsUpNotifier(controller: environment.controller)
        headsUp = notifier
        environment.engine.onNotify = { [weak notifier] message in
            notifier?.postInfo(message, id: "trigger-\(UUID().uuidString)")
        }
        environment.controller.onSafetyRelease = { [weak notifier] labels in
            notifier?.postInfo("Safety limit reached, so keep-awake stopped: \(labels.joined(separator: ", ")).",
                               id: "safety-cap")
        }
        environment.safety.onThermalRelease = { [weak notifier] in
            notifier?.postInfo("Your Mac got too hot, so EyesUpGuardian let it sleep.", id: "thermal")
        }
```

- [ ] **Step 5: Build and run the suite**

Run: `make app && make test`
Expected: the build succeeds with no warnings, and all tests pass.

- [ ] **Step 6: Verify the engine drives real assertions**

Run: this writes a trigger that fires while Finder is running, then checks macOS agrees.
```bash
cat > "$HOME/Library/Application Support/EyesUpGuardian/triggers.json" <<'JSON'
{"schemaVersion":1,"value":[{"id":"11111111-2222-3333-4444-555555555555","name":"While Finder is open","condition":{"appRunning":{"bundleIDs":["com.apple.finder"]}},"policy":1,"grace":0,"notifyOnChange":false,"isEnabled":true}]}
JSON
open build/EyesUpGuardian.app && sleep 4 && pmset -g assertions | grep "EyesUpGuardian:"
```
Expected: a line reading `PreventUserIdleSystemSleep named: "EyesUpGuardian: While Finder is open"`.

Then run: `osascript -e 'tell application id "dev.eyesupguardian.EyesUpGuardian" to quit'; rm "$HOME/Library/Application Support/EyesUpGuardian/triggers.json"`
Expected: no error. (The next task's UI creates triggers properly.)

- [ ] **Step 7: Commit**

```bash
git add Sources/EyesUpApp
git commit -m "feat(app): wire the trigger engine, settings and safety guard into the app" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 13: Dashboard window shell

**Files:**
- Create: `Sources/EyesUpApp/Dashboard/DashboardWindow.swift`
- Modify: `Sources/EyesUpApp/MenuBar/StatusItemController.swift` (menu item + callback)
- Modify: `Sources/EyesUpApp/Popover/PopoverView.swift` (footer button)
- Modify: `Sources/EyesUpApp/EyesUpGuardianApp.swift` (own the window controller)

**Interfaces:**
- Consumes: `AppEnvironment`, `AmbientBackground` (Plan 1).
- Produces:
  - `@Observable final class DashboardState { enum Tab { triggers, settings }; var tab; var editingDraft: TriggerDraft?; var errorMessage: String? }`
  - `DashboardWindowController(environment:)` with `show()`
  - `DashboardView(environment:state:)`
  - `StatusItemController.onOpenDashboard: (() -> Void)?`
  - `PopoverView(controller:form:onOpenDashboard:)`

Task 14 writes `TriggersTab` and `TriggerDraft`; Task 15 writes `SettingsTab`. To keep this task's build green, create both tab views as one-line placeholders here and replace them in their own tasks.

- [ ] **Step 1: Write the window, state and placeholder tabs**

`Sources/EyesUpApp/Dashboard/DashboardWindow.swift`:
```swift
import AppKit
import EyesUpCore
import SwiftUI

/// Which tab is showing and which sheet is open. A class because `@State` is unavailable
/// with the Command Line Tools (see the plan's Global Constraints).
@MainActor
@Observable
final class DashboardState {
    enum Tab: String, CaseIterable, Identifiable, Hashable {
        case triggers, settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .triggers: "Triggers"
            case .settings: "Settings"
            }
        }

        var symbol: String {
            switch self {
            case .triggers: "bolt.badge.clock"
            case .settings: "gearshape"
            }
        }
    }

    var tab: Tab = .triggers
    var editingDraft: TriggerDraft?
    var errorMessage: String?
}

/// Owns the single dashboard window. Reused if it's already open.
@MainActor
final class DashboardWindowController {
    private let environment: AppEnvironment
    private let state = DashboardState()
    private var window: NSWindow?

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "EyesUpGuardian"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: DashboardView(environment: environment, state: state))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        self.window = window
    }
}

struct DashboardView: View {
    let environment: AppEnvironment
    @Bindable var state: DashboardState

    var body: some View {
        NavigationSplitView {
            List(DashboardState.Tab.allCases, selection: $state.tab) { tab in
                Label(tab.title, systemImage: tab.symbol).tag(tab)
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 180, max: 240)
        } detail: {
            ZStack {
                AmbientBackground(mood: environment.controller.isAwake ? .awake : .idle)
                switch state.tab {
                case .triggers: TriggersTab(environment: environment, state: state)
                case .settings: SettingsTab(environment: environment)
                }
            }
        }
        .frame(minWidth: 700, minHeight: 460)
    }
}

// Replaced in Task 14.
struct TriggersTab: View {
    let environment: AppEnvironment
    @Bindable var state: DashboardState
    var body: some View { Text("Triggers").padding() }
}

// Replaced in Task 15.
struct SettingsTab: View {
    let environment: AppEnvironment
    var body: some View { Text("Settings").padding() }
}

// Replaced in Task 14.
@MainActor
@Observable
final class TriggerDraft: Identifiable {
    let id = UUID()
}
```

- [ ] **Step 2: Add the ways to open it**

In `Sources/EyesUpApp/MenuBar/StatusItemController.swift`:
1. Add a stored property after `private var minuteTimer: Timer?`:
```swift
    /// Set by the app delegate; shows the dashboard window.
    var onOpenDashboard: (() -> Void)?
```
2. In `showQuickMenu()`, insert before the `menu.addItem(.separator())` line:
```swift
        menu.addItem(menuItem("Open Dashboard…", #selector(openDashboard)))
```
3. Add next to the other `@objc` actions:
```swift
    @objc private func openDashboard() { onOpenDashboard?() }
```

In `Sources/EyesUpApp/Popover/PopoverView.swift`:
1. Add a stored property after `let controller: AwakeController`:
```swift
    let onOpenDashboard: () -> Void
```
2. Replace the footer's contents:
```swift
    private var footer: some View {
        HStack {
            Text("EyesUpGuardian").font(.caption2).foregroundStyle(.tertiary)
            Spacer()
            Button("Dashboard ↗") { onOpenDashboard() }
                .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
        }
    }
```

In `Sources/EyesUpApp/EyesUpGuardianApp.swift`:
1. Add a stored property to `AppDelegate`:
```swift
    private var dashboard: DashboardWindowController?
```
2. Replace the status-item setup lines with:
```swift
        let dashboard = DashboardWindowController(environment: environment)
        let statusItem = StatusItemController(controller: environment.controller)
        statusItem.onOpenDashboard = { dashboard.show() }
        statusItem.setPopoverContent(PopoverView(
            controller: environment.controller,
            form: PopoverFormState(),
            onOpenDashboard: { dashboard.show() }
        ))
        self.dashboard = dashboard
        self.statusItem = statusItem
```

- [ ] **Step 3: Build and check the window**

Run: `make app && make test`
Expected: the build succeeds and all tests pass.
Run: `open build/EyesUpGuardian.app`, then right-click the menu-bar ring and choose **Open Dashboard…**.
Expected: a window titled EyesUpGuardian opens with a sidebar showing Triggers and Settings, and the Ambient glow behind it. Clicking each sidebar row switches the placeholder text. Closing the window and choosing Open Dashboard… again reopens the same window.
Then quit the app.

- [ ] **Step 4: Commit**

```bash
git add Sources/EyesUpApp
git commit -m "feat(app): add the dashboard window with Triggers and Settings tabs" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 14: Triggers tab and editor

**Files:**
- Create: `Sources/EyesUpApp/Dashboard/TriggerDraft.swift`, `Sources/EyesUpApp/Dashboard/TriggersTab.swift`, `Sources/EyesUpApp/Dashboard/TriggerEditorSheet.swift`
- Modify: `Sources/EyesUpApp/Dashboard/DashboardWindow.swift` (delete the three placeholders: `TriggersTab`, `TriggerDraft`; keep `SettingsTab` until Task 15)
- Create: `Tests/EyesUpAppTests/TriggerDraftTests.swift`

**Interfaces:**
- Consumes: `TriggerEngine`, `Trigger`, `TriggerValidator`, `TriggerSuggestions`, `LiveWorkspaceEvents.runningApps()`, `LiveDisplayInventory.connectedDisplays()`, `DashboardState`.
- Produces: `TriggerDraft` (`init(kind:)`, `init(trigger:)`, `makeTrigger() -> Trigger?`, `defaultName`), `TriggersTab`, `TriggerEditorSheet`.

- [ ] **Step 1: Write the failing tests**

`Tests/EyesUpAppTests/TriggerDraftTests.swift`:
```swift
import EyesUpCore
import Foundation
import Testing
@testable import EyesUpApp

@Suite @MainActor struct TriggerDraftTests {
    @Test func newDraftBecomesAValidTrigger() throws {
        let draft = TriggerDraft(kind: .appRunning)
        draft.bundleIDs = ["com.anthropic.claudefordesktop"]
        draft.name = "Claude running"
        draft.graceMinutes = 5
        draft.keepDisplayOn = true

        let trigger = try #require(draft.makeTrigger())
        #expect(trigger.name == "Claude running")
        #expect(trigger.condition == .appRunning(bundleIDs: ["com.anthropic.claudefordesktop"]))
        #expect(trigger.grace == 300)
        #expect(trigger.policy == [.system, .display])
    }

    @Test func anEmptyNameFallsBackToTheKindTitle() throws {
        let draft = TriggerDraft(kind: .onACPower)
        let trigger = try #require(draft.makeTrigger())
        #expect(trigger.name == TriggerDraft.Kind.onACPower.title)
    }

    @Test func megabytesConvertToBytesPerSecond() throws {
        let draft = TriggerDraft(kind: .networkBusy)
        draft.megabytesPerSecond = 2.5
        draft.sustainMinutes = 1
        draft.releaseMinutes = 3
        let trigger = try #require(draft.makeTrigger())
        #expect(trigger.condition == .networkBusy(ActivityThreshold(value: 2_500_000, sustain: 60, release: 180)))
    }

    @Test func processNamesAreSplitOnCommas() throws {
        let draft = TriggerDraft(kind: .processRunning)
        draft.processNames = " node , claude,, swift-build "
        let trigger = try #require(draft.makeTrigger())
        #expect(trigger.condition == .processRunning(names: ["node", "claude", "swift-build"]))
    }

    @Test func incompleteDraftsMakeNoTrigger() {
        #expect(TriggerDraft(kind: .appRunning).makeTrigger() == nil)          // no apps chosen
        #expect(TriggerDraft(kind: .processRunning).makeTrigger() == nil)      // no names typed
        #expect(TriggerDraft(kind: .displayConnected).makeTrigger() == nil)    // no display chosen
        let outOfRange = TriggerDraft(kind: .cpuBusy)
        outOfRange.cpuPercent = 0
        #expect(outOfRange.makeTrigger() == nil)
    }

    @Test func editingKeepsTheTriggerIdentity() throws {
        let original = Trigger(name: "Weekdays", condition: .schedule(Schedule(weekdays: [2, 3], startMinute: 540, endMinute: 1080)),
                               policy: .system, grace: 600, notifyOnChange: true, isEnabled: false)
        let draft = TriggerDraft(trigger: original)
        #expect(draft.kind == .schedule)
        #expect(draft.weekdays == [2, 3])
        #expect(draft.graceMinutes == 10)
        #expect(!draft.isEnabled)

        let rebuilt = try #require(draft.makeTrigger())
        #expect(rebuilt.id == original.id)
        #expect(rebuilt == original)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test`
Expected: FAIL to compile with `value of type 'TriggerDraft' has no member 'bundleIDs'` (the Task 13 placeholder).

- [ ] **Step 3: Write the draft**

`Sources/EyesUpApp/Dashboard/TriggerDraft.swift`:
```swift
import EyesUpCore
import Foundation

/// The editable form behind the trigger sheet. `makeTrigger()` returns a validated trigger, or nil
/// when the form isn't usable yet, so the Save button can stay disabled.
@MainActor
@Observable
final class TriggerDraft: Identifiable {
    enum Kind: String, CaseIterable, Identifiable, Hashable {
        case appRunning, processRunning, schedule, cpuBusy, networkBusy, diskBusy, displayConnected, onACPower

        var id: String { rawValue }

        var title: String {
            switch self {
            case .appRunning: "While an app is open"
            case .processRunning: "While a command is running"
            case .schedule: "On a schedule"
            case .cpuBusy: "While the CPU is busy"
            case .networkBusy: "While the network is busy"
            case .diskBusy: "While the disk is busy"
            case .displayConnected: "While a display is connected"
            case .onACPower: "While on AC power"
            }
        }
    }

    let id: UUID
    let isNew: Bool
    var kind: Kind
    var name = ""
    var bundleIDs: [String] = []
    /// Comma separated, e.g. "node, claude".
    var processNames = ""
    var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    var startMinute = 9 * 60
    var endMinute = 18 * 60
    var cpuPercent = 40.0
    var megabytesPerSecond = 1.0
    var sustainMinutes = 2.0
    var releaseMinutes = 5.0
    var display: DisplayMatch?
    var keepDisplayOn = false
    var graceMinutes = 5.0
    var notifyOnChange = false
    var isEnabled = true

    init(kind: Kind = .appRunning) {
        id = UUID()
        isNew = true
        self.kind = kind
    }

    init(trigger: Trigger) {
        id = trigger.id
        isNew = false
        name = trigger.name
        keepDisplayOn = trigger.policy.contains(.display)
        graceMinutes = trigger.grace / 60
        notifyOnChange = trigger.notifyOnChange
        isEnabled = trigger.isEnabled

        switch trigger.condition {
        case .appRunning(let ids):
            kind = .appRunning
            bundleIDs = ids
        case .processRunning(let names):
            kind = .processRunning
            processNames = names.joined(separator: ", ")
        case .schedule(let schedule):
            kind = .schedule
            weekdays = schedule.weekdays
            startMinute = schedule.startMinute
            endMinute = schedule.endMinute
        case .cpuBusy(let threshold):
            kind = .cpuBusy
            cpuPercent = threshold.value
            sustainMinutes = threshold.sustain / 60
            releaseMinutes = threshold.release / 60
        case .networkBusy(let threshold):
            kind = .networkBusy
            megabytesPerSecond = threshold.value / 1_000_000
            sustainMinutes = threshold.sustain / 60
            releaseMinutes = threshold.release / 60
        case .diskBusy(let threshold):
            kind = .diskBusy
            megabytesPerSecond = threshold.value / 1_000_000
            sustainMinutes = threshold.sustain / 60
            releaseMinutes = threshold.release / 60
        case .displayConnected(let match):
            kind = .displayConnected
            display = match
        case .onACPower:
            kind = .onACPower
        }
    }

    var defaultName: String { kind.title }

    func makeTrigger() -> Trigger? {
        let sustain = sustainMinutes * 60
        let release = releaseMinutes * 60
        let condition: TriggerCondition

        switch kind {
        case .appRunning:
            condition = .appRunning(bundleIDs: bundleIDs)
        case .processRunning:
            let names = processNames.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            condition = .processRunning(names: names)
        case .schedule:
            condition = .schedule(Schedule(weekdays: weekdays, startMinute: startMinute, endMinute: endMinute))
        case .cpuBusy:
            condition = .cpuBusy(ActivityThreshold(value: cpuPercent.rounded(), sustain: sustain, release: release))
        case .networkBusy:
            condition = .networkBusy(ActivityThreshold(value: megabytesPerSecond * 1_000_000, sustain: sustain, release: release))
        case .diskBusy:
            condition = .diskBusy(ActivityThreshold(value: megabytesPerSecond * 1_000_000, sustain: sustain, release: release))
        case .displayConnected:
            guard let display else { return nil }
            condition = .displayConnected(display)
        case .onACPower:
            condition = .onACPower
        }

        return TriggerValidator.sanitized(Trigger(
            id: id,
            name: name.trimmingCharacters(in: .whitespaces).isEmpty ? defaultName : name,
            condition: condition,
            policy: keepDisplayOn ? [.system, .display] : .system,
            grace: graceMinutes * 60,
            notifyOnChange: notifyOnChange,
            isEnabled: isEnabled
        ))
    }
}
```

Delete the placeholder `TriggerDraft` and `TriggersTab` from `DashboardWindow.swift`.

- [ ] **Step 4: Write the tab**

`Sources/EyesUpApp/Dashboard/TriggersTab.swift`:
```swift
import EyesUpCore
import SwiftUI

struct TriggersTab: View {
    let environment: AppEnvironment
    @Bindable var state: DashboardState

    private var engine: TriggerEngine { environment.engine }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                suggestions
                if engine.triggers.isEmpty {
                    Text("No triggers yet. Add one to let your Mac stay awake by itself.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                }
                ForEach(engine.triggers) { trigger in
                    row(for: trigger)
                }
                if let notice = engine.storeNotice {
                    Label(notice, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                }
                if let message = state.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                }
            }
            .padding(20)
        }
        .sheet(item: $state.editingDraft) { draft in
            TriggerEditorSheet(environment: environment, state: state, draft: draft)
        }
    }

    private var header: some View {
        HStack {
            Text("Triggers").font(.title2.bold())
            Spacer()
            pauseMenu
            Menu {
                ForEach(TriggerDraft.Kind.allCases) { kind in
                    Button(kind.title) { state.editingDraft = TriggerDraft(kind: kind) }
                }
            } label: {
                Label("New trigger", systemImage: "plus")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private var pauseMenu: some View {
        Menu {
            Button("Pause for 1 hour") { environment.settings.update { $0.triggerPause = .until(Date().addingTimeInterval(3600)) } }
            Button("Pause for 4 hours") { environment.settings.update { $0.triggerPause = .until(Date().addingTimeInterval(4 * 3600)) } }
            Button("Pause until I resume") { environment.settings.update { $0.triggerPause = .untilResumed } }
            Divider()
            Button("Resume triggers") { environment.settings.update { $0.triggerPause = .none } }
                .disabled(!engine.isPaused)
        } label: {
            Label(engine.isPaused ? "Paused" : "Pause", systemImage: engine.isPaused ? "pause.circle.fill" : "pause.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .tint(engine.isPaused ? .orange : .secondary)
    }

    @ViewBuilder
    private var suggestions: some View {
        let running = environment.workspace.runningBundleIDs()
        let offers = TriggerSuggestions.suggestions(running: running, existing: engine.triggers)
        if !offers.isEmpty && !engine.isPaused {
            ForEach(offers) { offer in
                HStack {
                    Image(systemName: "lightbulb").foregroundStyle(.orange)
                    Text("\(offer.displayName) is running. Keep your Mac awake while it is?")
                    Spacer()
                    Button("Add") { add(suggestion: offer) }
                        .buttonStyle(.glassProminent)
                        .tint(.orange)
                }
                .padding(10)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func row(for trigger: Trigger) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(trigger.name).font(.headline)
                Text(trigger.summary).font(.callout).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    if trigger.policy.contains(.display) { Label("Display on", systemImage: "sun.max").font(.caption2) }
                    if trigger.grace > 0 { Label("+\(TimeFormatting.duration(trigger.grace)) after", systemImage: "hourglass").font(.caption2) }
                    if trigger.notifyOnChange { Label("Notifies", systemImage: "bell").font(.caption2) }
                    if environment.controller.hasTriggerHold(triggerID: trigger.id) {
                        Label("Active now", systemImage: "bolt.fill").font(.caption2).foregroundStyle(.orange)
                    }
                }
                .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { trigger.isEnabled },
                set: { engine.setEnabled($0, id: trigger.id) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .tint(.orange)
            Button {
                state.editingDraft = TriggerDraft(trigger: trigger)
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Edit \(trigger.name)")
            Button {
                engine.remove(id: trigger.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Delete \(trigger.name)")
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        .opacity(trigger.isEnabled ? 1 : 0.55)
    }

    private func add(suggestion: TriggerSuggestion) {
        let draft = TriggerDraft(kind: .appRunning)
        draft.bundleIDs = [suggestion.bundleID]
        draft.name = "\(suggestion.displayName) is open"
        guard let trigger = draft.makeTrigger() else { return }
        do {
            try engine.add(trigger)
            state.errorMessage = nil
        } catch {
            state.errorMessage = TriggerError.invalid.message
        }
    }
}
```

- [ ] **Step 5: Write the editor sheet**

`Sources/EyesUpApp/Dashboard/TriggerEditorSheet.swift`:
```swift
import EyesUpCore
import SwiftUI

struct TriggerEditorSheet: View {
    let environment: AppEnvironment
    @Bindable var state: DashboardState
    @Bindable var draft: TriggerDraft

    private let weekdayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(draft.isNew ? "New trigger" : "Edit trigger").font(.title3.bold())

            Form {
                Picker("Keep awake", selection: $draft.kind) {
                    ForEach(TriggerDraft.Kind.allCases) { kind in Text(kind.title).tag(kind) }
                }
                .disabled(!draft.isNew)

                TextField("Name", text: $draft.name, prompt: Text(draft.defaultName))

                conditionFields

                Section {
                    Toggle("Keep the display on too", isOn: $draft.keepDisplayOn)
                    Toggle("Notify me when it starts and stops", isOn: $draft.notifyOnChange)
                    LabeledContent("Stay awake after it ends") {
                        Stepper("\(Int(draft.graceMinutes)) min", value: $draft.graceMinutes, in: 0...120, step: 1)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { state.editingDraft = nil }
                Button(draft.isNew ? "Add trigger" : "Save") { save() }
                    .buttonStyle(.glassProminent)
                    .tint(.orange)
                    .disabled(draft.makeTrigger() == nil)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    @ViewBuilder
    private var conditionFields: some View {
        switch draft.kind {
        case .appRunning:
            Section("Apps") {
                ForEach(environment.workspace.runningApps(), id: \.bundleID) { app in
                    Toggle(app.name, isOn: Binding(
                        get: { draft.bundleIDs.contains(app.bundleID) },
                        set: { isOn in
                            if isOn { draft.bundleIDs.append(app.bundleID) }
                            else { draft.bundleIDs.removeAll { $0 == app.bundleID } }
                        }
                    ))
                }
                if draft.bundleIDs.isEmpty {
                    Text("Pick at least one app.").font(.caption).foregroundStyle(.secondary)
                }
            }
        case .processRunning:
            Section("Command names") {
                TextField("node, claude, swift-build", text: $draft.processNames)
                Text("Separate names with commas. Only processes you own are visible, so commands run with sudo can't be matched.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .schedule:
            Section("Days and times") {
                HStack {
                    ForEach(1...7, id: \.self) { day in
                        Toggle(weekdayNames[day - 1], isOn: Binding(
                            get: { draft.weekdays.contains(day) },
                            set: { isOn in
                                if isOn { draft.weekdays.insert(day) } else { draft.weekdays.remove(day) }
                            }
                        ))
                        .toggleStyle(.button)
                    }
                }
                Stepper("From \(Schedule.time(draft.startMinute))", value: $draft.startMinute, in: 0...1439, step: 15)
                Stepper("To \(Schedule.time(draft.endMinute))", value: $draft.endMinute, in: 0...1439, step: 15)
                Text("An end time earlier than the start means the window runs past midnight.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .cpuBusy:
            Section("Busy means") {
                LabeledContent("CPU above") {
                    Slider(value: $draft.cpuPercent, in: 5...95, step: 5) { Text("CPU") }
                        .frame(width: 200)
                    Text("\(Int(draft.cpuPercent))%").monospacedDigit()
                }
                busyTimings
            }
        case .networkBusy, .diskBusy:
            Section("Busy means") {
                LabeledContent(draft.kind == .networkBusy ? "Traffic above" : "Writes above") {
                    Stepper("\(draft.megabytesPerSecond, format: .number.precision(.fractionLength(1))) MB/s",
                            value: $draft.megabytesPerSecond, in: 0.1...500, step: 0.5)
                }
                busyTimings
            }
        case .displayConnected:
            Section("Display") {
                Picker("Display", selection: Binding(
                    get: { draft.display?.serial },
                    set: { serial in
                        draft.display = LiveDisplayInventory().connectedDisplays().first { $0.serial == serial }
                    }
                )) {
                    Text("Choose…").tag(UInt32?.none)
                    ForEach(LiveDisplayInventory().connectedDisplays(), id: \.serial) { display in
                        Text(display.name).tag(UInt32?.some(display.serial))
                    }
                }
            }
        case .onACPower:
            Text("Useful on a laptop: your Mac stays awake whenever it's plugged in.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var busyTimings: some View {
        Group {
            Stepper("Busy for at least \(Int(draft.sustainMinutes)) min", value: $draft.sustainMinutes, in: 0...60, step: 1)
            Stepper("Quiet for \(Int(draft.releaseMinutes)) min before releasing", value: $draft.releaseMinutes, in: 0...60, step: 1)
        }
    }

    private func save() {
        guard let trigger = draft.makeTrigger() else { return }
        do {
            if draft.isNew {
                try environment.engine.add(trigger)
            } else {
                try environment.engine.update(trigger)
            }
            state.errorMessage = nil
            state.editingDraft = nil
        } catch {
            state.errorMessage = TriggerError.invalid.message
        }
    }
}
```

- [ ] **Step 6: Run the tests and build**

Run: `make test && make app`
Expected: the 6 `TriggerDraftTests` pass along with everything else, and the app builds with no warnings.

- [ ] **Step 7: Verify by hand**

Run: `open build/EyesUpGuardian.app`, open the dashboard, and check:

| Action | Expected |
|---|---|
| Triggers tab with Finder/Claude running | A suggestion card offers the running app |
| Click **Add** on the suggestion | A trigger appears, marked "Active now", and `pmset -g assertions \| grep EyesUpGuardian` shows its name |
| Turn the trigger's switch off | The row dims and the assertion disappears |
| **New trigger → While a command is running**, type `sleep`, save. Then run `sleep 120` in Terminal | Within ~10 s the trigger shows "Active now" and the assertion appears; when `sleep` ends it clears within ~10 s |
| Edit that trigger, set "Stay awake after it ends" to 1 min | After the command ends, the hold lingers about a minute |
| **New trigger → On a schedule**, pick today, from a minute ahead to two minutes ahead | The trigger activates and releases at those times |
| **Pause → Pause until I resume** | All trigger holds clear, the menu shows Paused, and new conditions do nothing |
| **Pause → Resume triggers** | Still-true conditions take their holds again |
| Delete a trigger | The row and any hold disappear |

Then quit the app.

- [ ] **Step 8: Commit**

```bash
git add Sources/EyesUpApp Tests/EyesUpAppTests
git commit -m "feat(app): add the Triggers tab, suggestions and trigger editor" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 15: Settings tab and the automation link

**Files:**
- Create: `Sources/EyesUpApp/Dashboard/SettingsTab.swift`
- Modify: `Sources/EyesUpApp/Dashboard/DashboardWindow.swift` (delete the `SettingsTab` placeholder)
- Modify: `Sources/EyesUpApp/Resources/Info.plist` (register `eyesup://`)
- Modify: `Sources/EyesUpApp/EyesUpGuardianApp.swift` (handle opened URLs)

**Interfaces:**
- Consumes: `SettingsController`, `AppSettings`, `AutomationParser`, `AwakeController.apply(_:)`, `AutomationError`, `AwakeError`.
- Produces: `SettingsTab(environment:)`, URL handling in `AppDelegate.application(_:open:)`.

- [ ] **Step 1: Write the Settings tab**

`Sources/EyesUpApp/Dashboard/SettingsTab.swift`:
```swift
import EyesUpCore
import SwiftUI

struct SettingsTab: View {
    let environment: AppEnvironment

    private var settings: AppSettings { environment.settings.settings }

    /// Off, plus the caps offered in the picker.
    private let capChoices: [Double?] = [nil, 1, 2, 4, 8, 12, 24, 48]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Settings").font(.title2.bold())

                Form {
                    Section("Safety") {
                        Picker("Never stay awake longer than", selection: Binding(
                            get: { settings.safetyCapHours },
                            set: { hours in environment.settings.update { $0.safetyCapHours = hours } }
                        )) {
                            ForEach(capChoices, id: \.self) { choice in
                                Text(choice.map { "\(Int($0)) hours" } ?? "No limit").tag(choice)
                            }
                        }
                        Toggle("Let my Mac sleep if it gets too hot", isOn: Binding(
                            get: { settings.thermalAutoRelease },
                            set: { on in environment.settings.update { $0.thermalAutoRelease = on } }
                        ))
                        Text("Both apply to every keep-awake session, including triggers.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    Section("Automation link") {
                        Toggle("Allow eyesup:// links", isOn: Binding(
                            get: { settings.automationEnabled },
                            set: { on in environment.settings.update { $0.automationEnabled = on } }
                        ))
                        Text("""
                        Off by default. When on, scripts can run:
                          open "eyesup://start?for=2h"
                          open "eyesup://start?for=90m&display=true"
                          open "eyesup://extend?by=30m"
                          open "eyesup://stop"
                        Links can only start, extend or stop their own session, never longer than 24 hours, \
                        and never anything else. They can't touch sessions you started yourself.
                        """)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    }

                    Section("Triggers") {
                        LabeledContent("Status") {
                            Text(pauseDescription)
                        }
                        Button("Resume triggers") {
                            environment.settings.update { $0.triggerPause = .none }
                        }
                        .disabled(!environment.engine.isPaused)
                    }
                }
                .formStyle(.grouped)

                if let notice = environment.settings.storeNotice {
                    Label(notice, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
    }

    private var pauseDescription: String {
        switch settings.triggerPause {
        case .none: "Running"
        case .untilResumed: "Paused until you resume them"
        case .until(let date): "Paused until " + date.formatted(date: .omitted, time: .shortened)
        }
    }
}
```

Delete the placeholder `SettingsTab` from `DashboardWindow.swift`.

- [ ] **Step 2: Register the URL scheme**

In `Sources/EyesUpApp/Resources/Info.plist`, add before the closing `</dict>`:
```xml
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>dev.eyesupguardian.EyesUpGuardian.automation</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>eyesup</string>
            </array>
        </dict>
    </array>
```

- [ ] **Step 3: Handle opened links**

In `Sources/EyesUpApp/EyesUpGuardianApp.swift`, add to `AppDelegate`:
```swift
    /// Spec §5.1. Every link is parsed strictly, and does nothing unless the user switched links on.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let environment else { return }
        guard environment.automationEnabled else {
            headsUp?.postInfo(AutomationError.disabled.message, id: "automation")
            return
        }
        for url in urls.prefix(5) {
            do {
                let command = try AutomationParser.parse(url, cap: environment.controller.safetyCap)
                headsUp?.postInfo(try environment.controller.apply(command), id: "automation")
            } catch let error as AutomationError {
                headsUp?.postInfo(error.message, id: "automation")
            } catch let error as AwakeError {
                headsUp?.postInfo(error.message, id: "automation")
            } catch {
                headsUp?.postInfo("That automation link couldn't be used.", id: "automation")
            }
        }
    }
```
Add `import EyesUpCore` to that file if it isn't there yet.

- [ ] **Step 4: Build and run the suite**

Run: `make app && make test`
Expected: the build succeeds with no warnings and all tests pass.

- [ ] **Step 5: Verify the link end to end**

Run: `make install && open /Applications/EyesUpGuardian.app` (LaunchServices registers the scheme from the installed copy), then in the dashboard's Settings turn **Allow eyesup:// links** on.

Run: `open "eyesup://start?for=2h"; sleep 2; pmset -g assertions | grep "EyesUpGuardian:"`
Expected: `EyesUpGuardian: Automation 2h`, and a banner saying the Mac will stay awake for 2h.

Run: `open "eyesup://extend?by=30m"; sleep 2; pmset -g assertions | grep "EyesUpGuardian:"`
Expected: the name changes to `Automation until <time>`.

Run: `open "eyesup://start?for=99h"; sleep 2; pmset -g assertions | grep "EyesUpGuardian:"`
Expected: unchanged, plus a banner saying a value isn't allowed.

Run: `open "eyesup://quit"; sleep 2; pgrep -x EyesUpGuardian`
Expected: the app is still running, with a banner naming the three valid commands.

Run: `open "eyesup://stop"; sleep 2; pmset -g assertions | grep "EyesUpGuardian:"`
Expected: no output.

Then turn the setting off and run `open "eyesup://start?for=1h"; sleep 2; pmset -g assertions | grep "EyesUpGuardian:"`
Expected: no output, plus a banner saying automation links are switched off.

- [ ] **Step 6: Commit**

```bash
git add Sources/EyesUpApp
git commit -m "feat(app): add the Settings tab and the opt-in eyesup:// automation link" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 16: Performance, docs and spec sync

**Files:**
- Modify: `docs/manual-test-checklist.md`, `README.md`
- Modify: `docs/superpowers/specs/2026-09-19-eyesupguardian-design.md` (record this plan's clarifications)

**Interfaces:**
- Consumes: everything above.
- Produces: the updated docs; no code changes.

- [ ] **Step 1: Check the idle budget with triggers running**

Run: create three triggers through the UI — an app trigger, a `sleep` process trigger and a CPU-busy trigger — then run `make perf`.
Expected: `PASS`, with idle CPU still below 0.1%. The polling monitors wake every 10 s and 15 s, which should not be measurable.
If it FAILS: do not raise the limit. Use superpowers:systematic-debugging to find what is running when nothing is visible.

- [ ] **Step 2: Add the new manual checks**

Append to `docs/manual-test-checklist.md`:
```markdown

## Triggers (Plan 2)
- [ ] Suggestion card appears for a running known app and adds a working trigger.
- [ ] App trigger: quitting and relaunching the app releases and re-takes the hold.
- [ ] Process trigger: `sleep 120` in Terminal takes the hold within ~10 s and releases within ~10 s of ending.
- [ ] Schedule trigger: activates and releases at the times set, including a window that crosses midnight.
- [ ] CPU trigger: a heavy build takes the hold after the "busy for" time, and it clears after the quiet time.
- [ ] Grace period keeps the Mac awake for the set minutes after the condition ends.
- [ ] Editing a trigger's condition swaps its monitor; deleting it clears the hold.
- [ ] Pause for 1 hour clears trigger holds; Resume re-takes them for conditions that are still true.
- [ ] A trigger with notifications on posts a banner when it starts and stops.

## Safety guards (Plan 2)
- [ ] Setting "never stay awake longer than 1 hour" ends an indefinite session after an hour with a banner.
- [ ] With the cap off, an indefinite session shows no end time again.

## Automation link (Plan 2)
- [ ] With links off, `open "eyesup://start?for=1h"` does nothing and explains why.
- [ ] With links on: start, extend and stop all work, and `eyesup://quit` is refused.
- [ ] `eyesup://stop` does not cancel a session started by hand.
```

- [ ] **Step 3: Document triggers in the README**

In `README.md`, insert after the feature list:
```markdown
## Automatic keep-awake

Triggers keep your Mac awake by themselves. Open the dashboard (right-click the menu-bar icon → Open Dashboard…) and add any of:

- **While an app is open** — for example Claude, Xcode or Docker
- **While a command is running** — for example `node`, `claude` or `swift-build` (your own processes only; macOS hides other users' processes)
- **On a schedule** — chosen weekdays and times, including windows that cross midnight
- **While the Mac is busy** — CPU, network or disk above a threshold you set
- **While a display is connected**, or **while on AC power**

Each trigger can keep the display on too, stay awake for a grace period after its condition ends, and notify you when it starts and stops. Pause them all from the Triggers tab.

**Safety guards** (Settings): never stay awake longer than a chosen number of hours, and let the Mac sleep if it gets too hot.

**Automation link** (off by default): once enabled, scripts can run `open "eyesup://start?for=2h"`, `eyesup://extend?by=30m` and `eyesup://stop`. Links can only touch their own session, never longer than 24 hours.
```

- [ ] **Step 4: Sync the spec with this plan's decisions**

In `docs/superpowers/specs/2026-09-19-eyesupguardian-design.md`:

1. In the §5 trigger table, replace the "Process running" detection cell text
```
A cheap process-list scan every 10 s **only while this trigger is enabled**, then an instant exit notice
```
with
```
A cheap process-list scan every 10 s **only while this trigger is enabled** (Plan 2 decision: polling only; the ≤10 s release delay sits inside the grace period anyway). Only processes this user owns are visible to libproc.
```

2. In §5.1, after the "**It can never** quit processes…" line, add:
```
- **`stop` ends only the session a link started.** A link can never cancel a session you started by hand.
```

3. In §7.3, after the sentence introducing the five tabs, add:
```
The window ships in stages: Triggers and Settings in Plan 2, Overview and Processes in Plan 3, History in Plan 4.
```

- [ ] **Step 5: Final verification**

Run: `make test && make test-integration && make perf`
Expected: all unit tests pass, the integration suite passes, and perf prints `PASS`.
Then work through the new sections of `docs/manual-test-checklist.md`.

- [ ] **Step 6: Commit**

```bash
git add docs README.md
git commit -m "docs: document triggers, safety guards and the automation link" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```
