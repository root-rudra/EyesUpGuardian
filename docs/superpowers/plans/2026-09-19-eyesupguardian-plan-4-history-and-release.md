# EyesUpGuardian Plan 4: History, Energy, Settings, Shortcuts and Release

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish the app — session history with energy cost in kWh and money, the complete Settings tab, launch at login, a global keyboard shortcut, HUD polish, an app icon — then pay off the deferred list and make the repo ready to publish on GitHub.

**Architecture:**
- A `HistoryStore` keeps three capped, append-only series (sessions, daily energy, sleep/wake events) in one JSON file, pruned to 90 days. A `HistoryRecorder` watches the controller's holds and turns edges into finished sessions; an `EnergyMeter` integrates watts into daily kWh.
- Everything user-visible that was deferred in Plans 1–3 lands here, so the app ships with no known rough edges rather than a list of them.
- Release plumbing (icon, CI, license, release script) is the last task, so the repo is publishable the moment the plan is done.

**Tech Stack:** Swift 6.2, SwiftUI + AppKit (macOS 26), ServiceManagement (`SMAppService.mainApp`), Carbon `RegisterEventHotKey`, Swift Testing, GitHub Actions. No third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-09-19-eyesupguardian-design.md` (§6.3 energy, §7.1 readout options, §7.3 History and Settings tabs, §7.4 HUD behaviour, §8 history file, §11 build and publish)

**Builds on:** branch `plan-1-core-menu-bar` with Plans 1–3 complete and the security audit applied.

## Both spiked APIs work

Checked on the target Mac before this plan was written:
- **`RegisterEventHotKey`** (Carbon) compiles under Swift 6 strict concurrency with a `@convention(c)` callback and an `Unmanaged` context box. `kVK_ANSI_E` is 14; ⌃⌥⌘ is `controlKey | optionKey | cmdKey` = 6400. It needs no Accessibility permission, unlike an event tap.
- **`SMAppService.mainApp`** is reachable and reports `.notRegistered` (raw 3) for an unregistered build, so status can drive the toggle without guessing.

## Global Constraints

Everything from Plans 1–3 still holds:

- `// swift-tools-version: 6.2`, `platforms: [.macOS(.v26)]`, Swift 6 strict concurrency, **zero third-party dependencies** (no `.package(`, `.binaryTarget(`, `.plugin(`, `.systemLibrary(`, `unsafeFlags`).
- App code never runs commands, never touches the network, never escalates privileges, never loads code at runtime. `SecurityGuardTests` fails the build otherwise; exceptions must be marked `// security-allow:` on the line that needs one.
- `EyesUpCore` must not import SwiftUI or AppKit. **Never use SwiftUI `@State`** — use an `@Observable` class with `@Bindable`.
- Run tests with `make test` / `make test-integration`, never bare `swift test`.
- Storage stays in `~/Library/Application Support/EyesUpGuardian/`: JSON, `schemaVersion`, atomic writes, files `0600` in a `0700` folder, opened with `O_NOFOLLOW` and refused unless a regular file.
- Text from outside the app goes through `SafeText.display(_:limit:)` before it is shown anywhere.
- Idle budget: **< 0.1% CPU over 60 s and ≤ 30 MB footprint in the default configuration**, enforced by `make perf`. Visible surfaces have the 1.5% budget.
- End every commit message with `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.

## Decisions this plan records

1. **History is capped by count as well as by age.** Spec §8 says 90 days; a tampered or long-lived file also gets hard caps (2,000 sessions, 400 energy days, 2,000 sleep/wake events) so the file cannot grow without bound, and the caps are applied *before* validation like everywhere else.
2. **Energy cost is opt-in and rate-driven.** With no electricity rate set, the app shows kWh only — never a made-up currency figure. Money is formatted with the system locale's currency symbol.
3. **The energy tally is the one thing that samples while nothing is visible** (spec §6.3), at 30 s. It is off unless watts are readable, and `make perf` must still pass with it on.
4. **Launch at login uses `SMAppService.mainApp` only.** No daemon, no agent, no privileged helper. The security guard is narrowed from "`SMAppService` anywhere" to the daemon/agent/login-item-by-identifier forms, because those are the escalation risk and `mainApp` is not.
5. **The global shortcut uses Carbon `RegisterEventHotKey`**, which needs no Accessibility permission. An event tap would need one and could read every keystroke; this app will never ask for that.
6. **The deferred list from Plans 1–3 is paid off here** (Tasks 10 and 11), rather than shipping with known rough edges.

## Review Focus

1. **A tampered or enormous `history.json`** must not slow the app down or show nonsense totals: caps applied before validation, absurd values dropped. Tests: Task 1 `historyIsCappedBeforeValidation`, `absurdEntriesAreDropped`.
2. **Energy accounting across sleep and clock changes** must not invent kilowatt-hours: a gap of hours must not integrate as if the Mac were awake. Tests: Task 2 `sleepGapsDoNotCountAsEnergy`, `clockGoingBackwardsIsIgnored`.
3. **A session that spans midnight, or a Mac that never sleeps for days**, must land in the right day buckets and still total correctly. Tests: Task 2 `energySplitsAcrossMidnight`, Task 3 `aSessionSpanningDaysIsRecordedOnce`.
4. **Launch at login refused by macOS** (unsigned copy, moved app, user says no in System Settings) must leave the toggle honest rather than lying about its state. Tests: Task 6 `toggleReflectsWhatTheSystemReports`, `aRefusedRegistrationIsReported`.
5. **The global shortcut colliding with another app's** must not silently do nothing: registration failure is surfaced, and the shortcut can be turned off. Tests: Task 7 `aRefusedHotKeyIsReported`, `disablingTheShortcutUnregistersIt`.

---

## File map

```
Sources/EyesUpCore/History/
├── HistoryModel.swift        Task 1: Session, EnergyDay, SleepWakeEvent, HistorySnapshot
├── HistoryStore.swift        Task 1: capped, pruned, validated persistence
├── EnergyMeter.swift         Task 2: watts → kWh, day buckets, cost
└── HistoryRecorder.swift     Task 3: holds → sessions, sleep/wake, energy ticks

Sources/EyesUpCore/Store/AppSettings.swift        MODIFY Tasks 5, 6, 7, 9: rate, presets, lead, policy, login, hotkey, readout
Sources/EyesUpCore/Automation/AutomationCommand.swift  (unchanged)
Sources/EyesUpApp/
├── Dashboard/HistoryTab.swift        Task 4
├── Dashboard/SettingsTab.swift       MODIFY Tasks 5, 6, 7, 9
├── Dashboard/DashboardWindow.swift   MODIFY Tasks 4, 7: History tab, ⌘1–⌘5
├── Login/LaunchAtLogin.swift         Task 6
├── HotKey/GlobalHotKey.swift         Task 7
├── HUD/HUDWindow.swift               MODIFY Task 8: snapping, fade, click-through
├── MenuBar/StatusItemController.swift MODIFY Tasks 8, 9, 10
├── Popover/PopoverView.swift         MODIFY Task 10: paused badge, notice clearing
├── Resources/AppIcon.icns            Task 12 (generated by Scripts/make-icon.swift)
└── Resources/Info.plist              MODIFY Task 12: CFBundleIconFile

Scripts/make-icon.swift               Task 12
Scripts/release.sh                    Task 13 (notarization slots in later)
.github/workflows/ci.yml              Task 13
LICENSE, CONTRIBUTING.md              Task 13
Tests/EyesUpCoreTests/HistoryTests.swift, EnergyMeterTests.swift, HistoryRecorderTests.swift,
  LaunchAtLoginTests.swift, HotKeyTests.swift   Tasks 1, 2, 3, 6, 7
Tests/EyesUpAppTests/                 Tasks 5, 10
```

---

### Task 1: History model and store

**Files:**
- Create: `Sources/EyesUpCore/History/HistoryModel.swift`, `Sources/EyesUpCore/History/HistoryStore.swift`, `Tests/EyesUpCoreTests/HistoryTests.swift`

**Interfaces:**
- Consumes: `JSONFileStore`, `SafeText`, `StorageLocation`.
- Produces:
  - `struct Session: Identifiable, Codable, Hashable, Sendable { id: UUID; startedAt: Date; endedAt: Date; reasons: [String]; source: String }` with `var duration: TimeInterval`
  - `struct EnergyDay: Codable, Hashable, Sendable { day: Date; kilowattHours: Double; awakeSeconds: TimeInterval }`
  - `struct SleepWakeEvent: Codable, Hashable, Sendable { at: Date; kind: Kind }`, `enum Kind: String, Codable, Sendable { slept, woke }`
  - `struct HistorySnapshot: Codable, Equatable, Sendable { sessions: [Session]; energy: [EnergyDay]; sleepWake: [SleepWakeEvent] }` with `sanitized(now:) -> HistorySnapshot`, `awakeSeconds(since:)`, `kilowattHours(since:)`
  - `@MainActor @Observable final class HistoryController`: `init(store:clock:)`, `snapshot`, `load()`, `record(session:)`, `record(event:)`, `addEnergy(kilowattHours:awakeSeconds:at:)`, `clear()`, `storeNotice`
  - Caps: `HistorySnapshot.maxSessions = 2000`, `maxEnergyDays = 400`, `maxEvents = 2000`, `retentionDays = 90`

- [ ] **Step 1: Write the failing tests**

`Tests/EyesUpCoreTests/HistoryTests.swift`:
```swift
import Foundation
import Testing
@testable import EyesUpCore

@Suite @MainActor struct HistoryTests {
    let clock = FakeClock()

    func tempStore() -> JSONFileStore<HistorySnapshot> {
        JSONFileStore(
            url: FileManager.default.temporaryDirectory.appendingPathComponent("EyesUpTests-\(UUID().uuidString)/history.json"),
            schemaVersion: 1
        )
    }

    private func session(_ offsetHours: Double, hours: Double = 1, reasons: [String] = ["Timer 1h"]) -> Session {
        let start = referenceDate.addingTimeInterval(offsetHours * 3600)
        return Session(startedAt: start, endedAt: start.addingTimeInterval(hours * 3600), reasons: reasons, source: "manual")
    }

    @Test func sessionsAndTotalsAddUp() {
        var snapshot = HistorySnapshot()
        snapshot.sessions = [session(-5, hours: 2), session(-2, hours: 0.5)]
        #expect(snapshot.awakeSeconds(since: referenceDate.addingTimeInterval(-24 * 3600), now: referenceDate) == 9000)
        #expect(snapshot.sessions.first?.duration == 7200)
    }

    @Test func historyIsPrunedByAge() {
        var snapshot = HistorySnapshot()
        snapshot.sessions = [session(-24 * 100), session(-24)] // 100 days old, 1 day old
        snapshot.energy = [
            EnergyDay(day: referenceDate.addingTimeInterval(-100 * 86_400), kilowattHours: 1, awakeSeconds: 3600),
            EnergyDay(day: referenceDate.addingTimeInterval(-86_400), kilowattHours: 2, awakeSeconds: 3600),
        ]
        let clean = snapshot.sanitized(now: referenceDate)
        #expect(clean.sessions.count == 1)
        #expect(clean.energy.count == 1)
    }

    @Test func historyIsCappedBeforeValidation() {
        var snapshot = HistorySnapshot()
        snapshot.sessions = (0..<(HistorySnapshot.maxSessions + 500)).map { session(-Double($0) / 24) }
        snapshot.sleepWake = (0..<(HistorySnapshot.maxEvents + 500)).map {
            SleepWakeEvent(at: referenceDate.addingTimeInterval(-Double($0) * 60), kind: .woke)
        }
        let clean = snapshot.sanitized(now: referenceDate)
        #expect(clean.sessions.count <= HistorySnapshot.maxSessions)
        #expect(clean.sleepWake.count <= HistorySnapshot.maxEvents)
    }

    @Test func absurdEntriesAreDropped() {
        var snapshot = HistorySnapshot()
        let start = referenceDate.addingTimeInterval(-3600)
        snapshot.sessions = [
            Session(startedAt: start, endedAt: start.addingTimeInterval(-60), reasons: [], source: "manual"),   // ends before it starts
            Session(startedAt: referenceDate.addingTimeInterval(86_400), endedAt: referenceDate.addingTimeInterval(90_000),
                    reasons: [], source: "manual"),                                                            // in the future
            Session(startedAt: start, endedAt: start.addingTimeInterval(400 * 86_400), reasons: [], source: "manual"), // absurd length
            session(-1, reasons: ["Timer 1h\u{202E}\u{000A}fake"]),                                             // spoofed reason
        ]
        snapshot.energy = [
            EnergyDay(day: referenceDate, kilowattHours: .nan, awakeSeconds: 0),
            EnergyDay(day: referenceDate, kilowattHours: -5, awakeSeconds: 0),
            EnergyDay(day: referenceDate.addingTimeInterval(-3600), kilowattHours: 1.5, awakeSeconds: 3600),
        ]
        let clean = snapshot.sanitized(now: referenceDate)
        #expect(clean.sessions.count == 1)
        #expect(clean.sessions.first?.reasons.first?.contains("\n") == false)
        #expect(clean.sessions.first?.reasons.first?.unicodeScalars.contains { $0.properties.generalCategory == .format } == false)
        #expect(clean.energy.count == 1)
        #expect(clean.energy.first?.kilowattHours == 1.5)
    }

    @Test func recordingPersistsAndReloads() throws {
        let store = tempStore()
        let controller = HistoryController(store: store, clock: clock)
        controller.record(session: session(-1))
        controller.record(event: SleepWakeEvent(at: referenceDate, kind: .slept))
        controller.addEnergy(kilowattHours: 0.25, awakeSeconds: 900, at: referenceDate)

        let reloaded = HistoryController(store: store, clock: clock)
        reloaded.load()
        #expect(reloaded.snapshot.sessions.count == 1)
        #expect(reloaded.snapshot.sleepWake.count == 1)
        #expect(reloaded.snapshot.energy.first?.kilowattHours == 0.25)
    }

    @Test func energyForOneDayAccumulates() {
        let controller = HistoryController(store: nil, clock: clock)
        controller.addEnergy(kilowattHours: 0.1, awakeSeconds: 600, at: referenceDate)
        controller.addEnergy(kilowattHours: 0.2, awakeSeconds: 600, at: referenceDate.addingTimeInterval(3600))
        #expect(controller.snapshot.energy.count == 1)
        #expect((controller.snapshot.energy.first?.kilowattHours ?? 0) - 0.3 < 0.0001)
    }

    @Test func clearRemovesEverything() throws {
        let store = tempStore()
        let controller = HistoryController(store: store, clock: clock)
        controller.record(session: session(-1))
        controller.clear()
        #expect(controller.snapshot.sessions.isEmpty)

        let reloaded = HistoryController(store: store, clock: clock)
        reloaded.load()
        #expect(reloaded.snapshot.sessions.isEmpty)
    }

    @Test func aCorruptHistoryStartsCleanWithANotice() throws {
        let store = tempStore()
        try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("nonsense".utf8).write(to: store.url)
        let controller = HistoryController(store: store, clock: clock)
        controller.load()
        #expect(controller.snapshot.sessions.isEmpty)
        #expect(controller.storeNotice != nil)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test`
Expected: FAIL to compile with `cannot find 'HistorySnapshot' in scope`.

- [ ] **Step 3: Write the model**

`Sources/EyesUpCore/History/HistoryModel.swift`:
```swift
import Foundation

/// One finished keep-awake session.
public struct Session: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var startedAt: Date
    public var endedAt: Date
    /// The labels that were holding at the moment it ended, e.g. ["Timer 2h", "Claude running"].
    public var reasons: [String]
    /// "manual", "trigger" or "automation".
    public var source: String

    public init(id: UUID = UUID(), startedAt: Date, endedAt: Date, reasons: [String], source: String) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.reasons = reasons
        self.source = source
    }

    public var duration: TimeInterval { max(0, endedAt.timeIntervalSince(startedAt)) }
}

/// Energy used on one calendar day, and how long the Mac was held awake that day.
public struct EnergyDay: Codable, Hashable, Sendable {
    public var day: Date
    public var kilowattHours: Double
    public var awakeSeconds: TimeInterval

    public init(day: Date, kilowattHours: Double, awakeSeconds: TimeInterval) {
        self.day = day
        self.kilowattHours = kilowattHours
        self.awakeSeconds = awakeSeconds
    }
}

public struct SleepWakeEvent: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case slept, woke
    }

    public var at: Date
    public var kind: Kind

    public init(at: Date, kind: Kind) {
        self.at = at
        self.kind = kind
    }
}

/// Everything the app remembers about the past (spec §8). Capped by count and pruned by age.
public struct HistorySnapshot: Codable, Equatable, Sendable {
    public static let retentionDays = 90.0
    public static let maxSessions = 2000
    public static let maxEnergyDays = 400
    public static let maxEvents = 2000
    /// Longest a single session may claim to have run.
    public static let maxSessionDuration: TimeInterval = 30 * 86_400
    public static let maxReasonLength = 200
    /// A day's energy above this is not believable for a desktop Mac and is dropped.
    public static let maxDailyKilowattHours = 100.0

    public var sessions: [Session] = []
    public var energy: [EnergyDay] = []
    public var sleepWake: [SleepWakeEvent] = []

    public init() {}

    public func awakeSeconds(since: Date, now: Date = Date()) -> TimeInterval {
        sessions.filter { $0.endedAt >= since && $0.startedAt <= now }.reduce(0) { $0 + $1.duration }
    }

    public func kilowattHours(since: Date) -> Double {
        energy.filter { $0.day >= since }.reduce(0) { $0 + $1.kilowattHours }
    }

    /// Caps first, then validates: a tampered file costs no more work than a normal one.
    public func sanitized(now: Date = Date()) -> HistorySnapshot {
        let oldest = now.addingTimeInterval(-Self.retentionDays * 86_400)
        var clean = HistorySnapshot()

        clean.sessions = sessions.suffix(Self.maxSessions).compactMap { session in
            guard session.endedAt > session.startedAt,
                  session.startedAt <= now,
                  session.endedAt >= oldest,
                  session.duration <= Self.maxSessionDuration else { return nil }
            var kept = session
            kept.reasons = session.reasons.prefix(8).map { SafeText.display($0, limit: Self.maxReasonLength) }
            kept.source = SafeText.display(session.source, limit: 20)
            return kept
        }

        clean.energy = energy.suffix(Self.maxEnergyDays).filter { day in
            day.kilowattHours.isFinite && day.kilowattHours >= 0 && day.kilowattHours <= Self.maxDailyKilowattHours
                && day.awakeSeconds.isFinite && day.awakeSeconds >= 0
                && day.day >= oldest && day.day <= now.addingTimeInterval(86_400)
        }

        clean.sleepWake = sleepWake.suffix(Self.maxEvents).filter { $0.at >= oldest && $0.at <= now }
        return clean
    }
}
```

- [ ] **Step 4: Write the controller**

`Sources/EyesUpCore/History/HistoryStore.swift`:
```swift
import Foundation
import Observation

/// Owns what the app remembers and writes it out. Everything it returns has already been sanitised.
@MainActor
@Observable
public final class HistoryController {
    public private(set) var snapshot = HistorySnapshot()
    public private(set) var storeNotice: String?

    @ObservationIgnored private let store: JSONFileStore<HistorySnapshot>?
    @ObservationIgnored private let clock: any WallClock

    public init(store: JSONFileStore<HistorySnapshot>?, clock: any WallClock = SystemClock()) {
        self.store = store
        self.clock = clock
    }

    public func load() {
        guard let store else { return }
        switch store.load(now: clock.now) {
        case .missing:
            break
        case .loaded(let saved):
            snapshot = saved.sanitized(now: clock.now)
        case .corrupt:
            storeNotice = "Your history couldn't be read, so it was reset."
        }
    }

    public func record(session: Session) {
        snapshot.sessions.append(session)
        persist()
    }

    public func record(event: SleepWakeEvent) {
        snapshot.sleepWake.append(event)
        persist()
    }

    /// Adds to today's bucket, creating it on the first tick of the day.
    public func addEnergy(kilowattHours: Double, awakeSeconds: TimeInterval, at date: Date) {
        guard kilowattHours.isFinite, kilowattHours >= 0 else { return }
        let day = Calendar.current.startOfDay(for: date)
        if let index = snapshot.energy.firstIndex(where: { Calendar.current.isDate($0.day, inSameDayAs: day) }) {
            snapshot.energy[index].kilowattHours += kilowattHours
            snapshot.energy[index].awakeSeconds += awakeSeconds
        } else {
            snapshot.energy.append(EnergyDay(day: day, kilowattHours: kilowattHours, awakeSeconds: awakeSeconds))
        }
        persist()
    }

    public func clear() {
        snapshot = HistorySnapshot()
        persist()
    }

    /// Called at launch and daily, so an app left running for months doesn't keep growing.
    public func prune() {
        snapshot = snapshot.sanitized(now: clock.now)
        persist()
    }

    private func persist() {
        guard let store else { return }
        do {
            try store.save(snapshot.sanitized(now: clock.now))
        } catch {
            storeNotice = "Couldn't save history: \(error.localizedDescription)"
        }
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `make test`
Expected: all 8 `HistoryTests` pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/EyesUpCore/History Tests/EyesUpCoreTests/HistoryTests.swift
git commit -m "feat(core): add capped, pruned session and energy history" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: Energy meter

**Files:**
- Create: `Sources/EyesUpCore/History/EnergyMeter.swift`, `Tests/EyesUpCoreTests/EnergyMeterTests.swift`

**Interfaces:**
- Consumes: nothing beyond Foundation.
- Produces:
  - `struct EnergyMeter: Sendable`: `mutating func accumulate(watts: Double, at: Date, awake: Bool) -> EnergyTick?`
  - `struct EnergyTick: Equatable, Sendable { kilowattHours: Double; awakeSeconds: TimeInterval; at: Date }`
  - `static let maxGap: TimeInterval = 120` — a longer gap means the Mac slept or the app was paused, and is not integrated
  - `enum EnergyCost { static func money(_ kilowattHours: Double, ratePerKilowattHour: Double?, locale: Locale) -> String? }`

- [ ] **Step 1: Write the failing tests**

`Tests/EyesUpCoreTests/EnergyMeterTests.swift`:
```swift
import Foundation
import Testing
@testable import EyesUpCore

@Suite struct EnergyMeterTests {
    @Test func firstSampleOnlySetsABaseline() {
        var meter = EnergyMeter()
        #expect(meter.accumulate(watts: 40, at: referenceDate, awake: true) == nil)
    }

    @Test func steadyDrawIntegratesToKilowattHours() throws {
        var meter = EnergyMeter()
        _ = meter.accumulate(watts: 36, at: referenceDate, awake: true)
        // 36 W for 100 s = 1 Wh = 0.001 kWh
        let tick = try #require(meter.accumulate(watts: 36, at: referenceDate.addingTimeInterval(100), awake: true))
        #expect(abs(tick.kilowattHours - 0.001) < 0.000_001)
        #expect(tick.awakeSeconds == 100)
    }

    @Test func timeWhileNotAwakeCountsEnergyButNotAwakeSeconds() throws {
        var meter = EnergyMeter()
        _ = meter.accumulate(watts: 36, at: referenceDate, awake: false)
        let tick = try #require(meter.accumulate(watts: 36, at: referenceDate.addingTimeInterval(100), awake: false))
        #expect(tick.kilowattHours > 0)
        #expect(tick.awakeSeconds == 0)
    }

    @Test func sleepGapsDoNotCountAsEnergy() {
        var meter = EnergyMeter()
        _ = meter.accumulate(watts: 36, at: referenceDate, awake: true)
        // The Mac slept for an hour: nothing was measured in between, so nothing is claimed.
        #expect(meter.accumulate(watts: 36, at: referenceDate.addingTimeInterval(3600), awake: true) == nil)
        // The next normal interval works again.
        #expect(meter.accumulate(watts: 36, at: referenceDate.addingTimeInterval(3630), awake: true) != nil)
    }

    @Test func clockGoingBackwardsIsIgnored() {
        var meter = EnergyMeter()
        _ = meter.accumulate(watts: 36, at: referenceDate, awake: true)
        #expect(meter.accumulate(watts: 36, at: referenceDate.addingTimeInterval(-60), awake: true) == nil)
    }

    @Test func absurdWattsAreIgnored() {
        var meter = EnergyMeter()
        _ = meter.accumulate(watts: 36, at: referenceDate, awake: true)
        #expect(meter.accumulate(watts: .nan, at: referenceDate.addingTimeInterval(30), awake: true) == nil)
        #expect(meter.accumulate(watts: 50_000, at: referenceDate.addingTimeInterval(60), awake: true) == nil)
    }

    @Test func energySplitsAcrossMidnight() throws {
        // A tick that straddles midnight is attributed to the moment it ended, so day buckets stay simple
        // and a long-running Mac doesn't pile a whole night onto one day.
        var meter = EnergyMeter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let beforeMidnight = calendar.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 23, minute: 59, second: 30))!
        _ = meter.accumulate(watts: 36, at: beforeMidnight, awake: true)
        let tick = try #require(meter.accumulate(watts: 36, at: beforeMidnight.addingTimeInterval(60), awake: true))
        #expect(calendar.component(.day, from: tick.at) == 22)
    }

    @Test func costNeedsARate() {
        #expect(EnergyCost.money(1.5, ratePerKilowattHour: nil, locale: Locale(identifier: "en_US")) == nil)
        let cost = EnergyCost.money(1.5, ratePerKilowattHour: 0.32, locale: Locale(identifier: "en_US"))
        #expect(cost?.contains("0.48") == true)
        #expect(EnergyCost.money(.nan, ratePerKilowattHour: 0.32, locale: Locale(identifier: "en_US")) == nil)
        #expect(EnergyCost.money(1, ratePerKilowattHour: -1, locale: Locale(identifier: "en_US")) == nil)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test`
Expected: FAIL to compile with `cannot find 'EnergyMeter' in scope`.

- [ ] **Step 3: Write the meter**

`Sources/EyesUpCore/History/EnergyMeter.swift`:
```swift
import Foundation

public struct EnergyTick: Equatable, Sendable {
    public var kilowattHours: Double
    public var awakeSeconds: TimeInterval
    /// The moment the interval ended; the day bucket is chosen from this.
    public var at: Date
}

/// Turns repeated power readings into energy. Gaps longer than `maxGap` are not integrated: the Mac
/// was asleep or the app wasn't sampling, and guessing would invent kilowatt-hours that never happened.
public struct EnergyMeter: Sendable {
    public static let maxGap: TimeInterval = 120
    /// No desktop Mac draws this much; a reading above it is a sensor fault, not electricity.
    public static let maxWatts = 2000.0

    private var lastTime: Date?

    public init() {}

    public mutating func accumulate(watts: Double, at now: Date, awake: Bool) -> EnergyTick? {
        defer { lastTime = now }
        guard watts.isFinite, watts >= 0, watts <= Self.maxWatts else { return nil }
        guard let last = lastTime else { return nil }
        let elapsed = now.timeIntervalSince(last)
        guard elapsed > 0, elapsed <= Self.maxGap else { return nil }

        let kilowattHours = watts * elapsed / 3_600_000
        return EnergyTick(kilowattHours: kilowattHours, awakeSeconds: awake ? elapsed : 0, at: now)
    }
}

public enum EnergyCost {
    /// Money for an amount of energy, or nil when there is no rate — the app never invents a figure.
    public static func money(_ kilowattHours: Double, ratePerKilowattHour: Double?, locale: Locale = .current) -> String? {
        guard let rate = ratePerKilowattHour, rate > 0, rate.isFinite,
              kilowattHours.isFinite, kilowattHours >= 0 else { return nil }
        let amount = kilowattHours * rate
        return amount.formatted(.currency(code: locale.currency?.identifier ?? "USD").locale(locale))
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `make test`
Expected: all 8 `EnergyMeterTests` pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/EyesUpCore/History/EnergyMeter.swift Tests/EyesUpCoreTests/EnergyMeterTests.swift
git commit -m "feat(core): add energy accounting that ignores sleep gaps" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: History recorder

**Files:**
- Create: `Sources/EyesUpCore/History/HistoryRecorder.swift`, `Tests/EyesUpCoreTests/HistoryRecorderTests.swift`
- Modify: `Sources/EyesUpApp/AppEnvironment.swift` (own the recorder and feed it)

**Interfaces:**
- Consumes: `AwakeController.holds`, `HistoryController`, `EnergyMeter`, `WallClock`, `TimerScheduling`, `MetricsCenter` (for watts).
- Produces:
  - `@MainActor final class HistoryRecorder`: `init(history:clock:)`, `holdsChanged(_ holds: [Hold])`, `recordSleep()`, `recordWake()`, `energyTick(watts:awake:)`, `finishOpenSession()`
  - `AppEnvironment.history: HistoryController`, `AppEnvironment.recorder: HistoryRecorder`

A session starts when the first hold appears and ends when the last one goes away; its reasons are the labels seen while it ran.

- [ ] **Step 1: Write the failing tests**

`Tests/EyesUpCoreTests/HistoryRecorderTests.swift`:
```swift
import Foundation
import Testing
@testable import EyesUpCore

@Suite @MainActor struct HistoryRecorderTests {
    let clock = FakeClock()

    func makeRecorder() -> (HistoryRecorder, HistoryController) {
        let history = HistoryController(store: nil, clock: clock)
        return (HistoryRecorder(history: history, clock: clock), history)
    }

    @Test func aSessionIsRecordedWhenTheLastHoldGoesAway() {
        let (recorder, history) = makeRecorder()
        recorder.holdsChanged([makeHold(label: "Timer 2h")])
        #expect(history.snapshot.sessions.isEmpty) // still running

        clock.advance(7200)
        recorder.holdsChanged([])
        #expect(history.snapshot.sessions.count == 1)
        #expect(history.snapshot.sessions.first?.duration == 7200)
        #expect(history.snapshot.sessions.first?.reasons.contains("Timer 2h") == true)
    }

    @Test func holdsComingAndGoingStayOneSession() {
        let (recorder, history) = makeRecorder()
        recorder.holdsChanged([makeHold(label: "Timer 2h")])
        clock.advance(600)
        recorder.holdsChanged([makeHold(label: "Timer 2h"), makeHold(label: "Claude running")])
        clock.advance(600)
        recorder.holdsChanged([makeHold(label: "Claude running")])
        clock.advance(600)
        recorder.holdsChanged([])
        #expect(history.snapshot.sessions.count == 1)
        #expect(history.snapshot.sessions.first?.duration == 1800)
        #expect(history.snapshot.sessions.first?.reasons.sorted() == ["Claude running", "Timer 2h"])
    }

    @Test func aSessionSpanningDaysIsRecordedOnce() {
        let (recorder, history) = makeRecorder()
        recorder.holdsChanged([makeHold(label: "Indefinitely")])
        clock.advance(3 * 86_400)
        recorder.holdsChanged([])
        #expect(history.snapshot.sessions.count == 1)
        #expect(history.snapshot.sessions.first?.duration == 3 * 86_400)
    }

    @Test func quittingWhileAwakeStillRecordsTheSession() {
        let (recorder, history) = makeRecorder()
        recorder.holdsChanged([makeHold(label: "Timer 1h")])
        clock.advance(1800)
        recorder.finishOpenSession()
        #expect(history.snapshot.sessions.count == 1)
        #expect(history.snapshot.sessions.first?.duration == 1800)
    }

    @Test func sleepAndWakeAreLogged() {
        let (recorder, history) = makeRecorder()
        recorder.recordSleep()
        clock.advance(3600)
        recorder.recordWake()
        #expect(history.snapshot.sleepWake.map(\.kind) == [.slept, .woke])
    }

    @Test func energyTicksLandInTheDayBucket() {
        let (recorder, history) = makeRecorder()
        recorder.energyTick(watts: 36, awake: true)
        clock.advance(100)
        recorder.energyTick(watts: 36, awake: true)
        #expect(history.snapshot.energy.count == 1)
        #expect((history.snapshot.energy.first?.kilowattHours ?? 0) > 0)
        #expect(history.snapshot.energy.first?.awakeSeconds == 100)
    }

    @Test func aSleepGapDoesNotInventEnergy() {
        let (recorder, history) = makeRecorder()
        recorder.energyTick(watts: 36, awake: true)
        clock.advance(4 * 3600)
        recorder.energyTick(watts: 36, awake: true)
        #expect(history.snapshot.energy.isEmpty)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test`
Expected: FAIL to compile with `cannot find 'HistoryRecorder' in scope`.

- [ ] **Step 3: Write the recorder**

`Sources/EyesUpCore/History/HistoryRecorder.swift`:
```swift
import Foundation

/// Turns what the controller is doing into what the History tab shows: one session per continuous
/// stretch of being awake, plus the sleep/wake log and the energy tally.
@MainActor
public final class HistoryRecorder {
    private let history: HistoryController
    private let clock: any WallClock
    private var sessionStart: Date?
    private var reasons: Set<String> = []
    private var sources: Set<String> = []
    private var meter = EnergyMeter()

    public init(history: HistoryController, clock: any WallClock = SystemClock()) {
        self.history = history
        self.clock = clock
    }

    /// Call whenever the controller's holds change.
    public func holdsChanged(_ holds: [Hold]) {
        if holds.isEmpty {
            finishOpenSession()
            return
        }
        if sessionStart == nil { sessionStart = clock.now }
        reasons.formUnion(holds.map(\.label))
        sources.formUnion(holds.map { hold in
            switch hold.source {
            case .manual: "manual"
            case .trigger: "trigger"
            case .automation: "automation"
            }
        })
    }

    /// Ends the running session, if any — on the last hold going away, and on quit.
    public func finishOpenSession() {
        guard let start = sessionStart else { return }
        sessionStart = nil
        let session = Session(
            startedAt: start,
            endedAt: clock.now,
            reasons: reasons.sorted(),
            source: sources.sorted().joined(separator: "+")
        )
        reasons.removeAll()
        sources.removeAll()
        guard session.duration > 0 else { return }
        history.record(session: session)
    }

    public func recordSleep() {
        history.record(event: SleepWakeEvent(at: clock.now, kind: .slept))
    }

    public func recordWake() {
        history.record(event: SleepWakeEvent(at: clock.now, kind: .woke))
        meter = EnergyMeter() // the gap across sleep is not energy we measured
    }

    /// One power reading. The meter decides whether enough time passed to count.
    public func energyTick(watts: Double, awake: Bool) {
        guard let tick = meter.accumulate(watts: watts, at: clock.now, awake: awake) else { return }
        history.addEnergy(kilowattHours: tick.kilowattHours, awakeSeconds: tick.awakeSeconds, at: tick.at)
    }
}
```

- [ ] **Step 4: Feed it from the app**

In `Sources/EyesUpApp/AppEnvironment.swift`:

1. Add properties beside the others:
```swift
    let history: HistoryController
    let recorder: HistoryRecorder
```
2. In `init()`, after `metrics` is built:
```swift
        history = HistoryController(
            store: JSONFileStore(url: directory.appendingPathComponent("history.json"), schemaVersion: 1)
        )
        recorder = HistoryRecorder(history: history)
```
3. In `start()`, after `settings.load()`:
```swift
        history.load()
        history.prune()
        observeHolds()
        startEnergyTally()
```
4. Add these two methods, and the sleep/wake logging, to the class:
```swift
    /// Sessions are recorded from the holds themselves, so every source counts the same way.
    private func observeHolds() {
        withObservationTracking {
            _ = controller.holds
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                recorder.holdsChanged(controller.holds)
                observeHolds()
            }
        }
        recorder.holdsChanged(controller.holds)
    }

    /// Spec §6.3: the one thing that samples while nothing is visible, at 30 s, and only when
    /// watts are actually readable.
    private func startEnergyTally() {
        energySubscription = metrics.subscribe([.power], interval: 30)
        energyTimer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let watts = metrics.snapshot.power?.watts else { return }
                recorder.energyTick(watts: watts, awake: controller.isAwake)
            }
        }
        energyTimer?.tolerance = 5
        if let energyTimer { RunLoop.main.add(energyTimer, forMode: .common) }
    }
```
with the two stored properties:
```swift
    private var energySubscription: MetricsSubscription?
    private var energyTimer: Timer?
```
5. In `start()`'s wake observer closure, add `self?.recorder.recordWake()`, and add a sleep observer beside it:
```swift
        observers.append(workspaceCenter.addObserver(forName: NSWorkspace.willSleepNotification,
                                                     object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.recorder.recordSleep() }
        })
```
6. In `shutdown()`, before `controller.shutdown()`:
```swift
        recorder.finishOpenSession()
        energySubscription?.cancel()
        energyTimer?.invalidate()
```

- [ ] **Step 5: Run the tests and check the idle budget**

Run: `make test && make app`
Expected: all 7 `HistoryRecorderTests` pass and the app builds with no warnings.
Run: `make perf`
Expected: **PASS**. The energy tally samples every 30 s, which must not breach the idle budget. If it fails, do not raise the limit — check that nothing else started sampling.

- [ ] **Step 6: Verify it records against the real app**

Run:
```bash
rm -f "$HOME/Library/Application Support/EyesUpGuardian/history.json"
open build/EyesUpGuardian.app && sleep 2
open "eyesup://start?for=2h" 2>/dev/null || true   # only if automation is on; otherwise use the menu
sleep 5
osascript -e 'tell application id "dev.eyesupguardian.EyesUpGuardian" to quit'
sleep 2
cat "$HOME/Library/Application Support/EyesUpGuardian/history.json"
```
Expected: a `sessions` entry with a start, an end and its reasons — quitting while awake must still record it.

- [ ] **Step 7: Commit**

```bash
git add Sources Tests
git commit -m "feat: record sessions, sleep/wake and energy as they happen" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: History tab

**Files:**
- Create: `Sources/EyesUpApp/Dashboard/HistoryTab.swift`
- Modify: `Sources/EyesUpApp/Dashboard/DashboardWindow.swift` (add the tab)

**Interfaces:**
- Consumes: `HistoryController.snapshot`, `EnergyCost.money`, `StatFormatting`, `TimeFormatting`, `AppSettings.electricityRate` (Task 5 adds it; until then the cost line reads kWh only).
- Produces: `struct HistoryTab: View`, `@Observable final class HistoryTabState { var range: HistoryRange }`, `enum HistoryRange: String, CaseIterable { week, month }`.

- [ ] **Step 1: Write the tab**

`Sources/EyesUpApp/Dashboard/HistoryTab.swift`:
```swift
import EyesUpCore
import SwiftUI

enum HistoryRange: String, CaseIterable, Identifiable {
    case week, month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: "7 days"
        case .month: "30 days"
        }
    }

    var days: Int {
        switch self {
        case .week: 7
        case .month: 30
        }
    }
}

@MainActor
@Observable
final class HistoryTabState {
    var range: HistoryRange = .week
}

/// What the Mac has been doing: how long it was kept awake, what kept it awake, what that cost,
/// and when it slept.
struct HistoryTab: View {
    let environment: AppEnvironment
    @Bindable var state: HistoryTabState

    private var snapshot: HistorySnapshot { environment.history.snapshot }
    private var since: Date { Calendar.current.startOfDay(for: Date().addingTimeInterval(-Double(state.range.days - 1) * 86_400)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                dayChart
                totals
                topReasons
                sessionList
                sleepLog
                if let notice = environment.history.storeNotice {
                    Label(notice, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
    }

    private var header: some View {
        HStack {
            Text("History").font(.title2.bold())
            Spacer()
            Picker("Range", selection: $state.range) {
                ForEach(HistoryRange.allCases) { range in Text(range.title).tag(range) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
        }
    }

    /// Hours kept awake per day, oldest on the left.
    private var dayChart: some View {
        let days = dailyAwakeHours()
        let tallest = max(days.map(\.hours).max() ?? 1, 0.5)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(days, id: \.day) { entry in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(entry.hours > 0 ? Color.orange.opacity(0.85) : Color.secondary.opacity(0.2))
                            .frame(height: max(3, CGFloat(entry.hours / tallest) * 90))
                            .accessibilityLabel("\(entry.label): \(TimeFormatting.duration(entry.hours * 3600)) awake")
                        Text(entry.label).font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 110, alignment: .bottom)
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }

    private var totals: some View {
        let awake = snapshot.awakeSeconds(since: since)
        let sessions = snapshot.sessions.filter { $0.endedAt >= since }
        let kilowattHours = snapshot.kilowattHours(since: since)
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
            StatTile(title: "Kept awake", value: TimeFormatting.duration(awake), detail: state.range.title, symbol: "eye")
            StatTile(title: "Sessions", value: "\(sessions.count)", detail: "in this range", symbol: "list.number")
            StatTile(title: "Energy", value: kilowattHours > 0 ? String(format: "%.2f kWh", kilowattHours) : StatFormatting.unavailable,
                     detail: energyDetail(kilowattHours), symbol: "bolt.circle")
            StatTile(title: "Longest", value: TimeFormatting.duration(sessions.map(\.duration).max() ?? 0),
                     detail: "single session", symbol: "hourglass")
        }
    }

    private func energyDetail(_ kilowattHours: Double) -> String {
        guard kilowattHours > 0 else { return "needs power readings" }
        // Task 5 adds `electricityRate` to the settings and swaps the nil below for it; until then
        // this reads "set a rate in Settings", which is also what an unset rate should say.
        return EnergyCost.money(kilowattHours, ratePerKilowattHour: nil) ?? "set a rate in Settings"
    }

    @ViewBuilder
    private var topReasons: some View {
        let ranked = rankedReasons()
        if !ranked.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("What kept it awake").font(.headline)
                ForEach(ranked.prefix(5), id: \.reason) { entry in
                    HStack {
                        Text(entry.reason).lineLimit(1)
                        Spacer()
                        Text(TimeFormatting.duration(entry.seconds)).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .font(.callout)
                }
            }
            .padding(12)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private var sessionList: some View {
        let sessions = snapshot.sessions.filter { $0.endedAt >= since }.sorted { $0.startedAt > $1.startedAt }
        VStack(alignment: .leading, spacing: 6) {
            Text("Sessions").font(.headline)
            if sessions.isEmpty {
                Text("Nothing yet in this range.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(sessions.prefix(50)) { session in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.callout)
                        Text(session.reasons.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Text(TimeFormatting.duration(session.duration)).monospacedDigit().font(.callout)
                }
                .padding(8)
                .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    @ViewBuilder
    private var sleepLog: some View {
        let events = snapshot.sleepWake.filter { $0.at >= since }.sorted { $0.at > $1.at }
        if !events.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Sleep and wake").font(.headline)
                ForEach(events.prefix(10), id: \.self) { event in
                    HStack {
                        Image(systemName: event.kind == .slept ? "moon.fill" : "sun.max.fill")
                            .foregroundStyle(event.kind == .slept ? .purple : .orange)
                        Text(event.kind == .slept ? "Went to sleep" : "Woke up")
                        Spacer()
                        Text(event.at.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }
            .padding(12)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func dailyAwakeHours() -> [(day: Date, label: String, hours: Double)] {
        let calendar = Calendar.current
        return (0..<state.range.days).reversed().map { offset in
            let day = calendar.startOfDay(for: Date().addingTimeInterval(-Double(offset) * 86_400))
            let next = day.addingTimeInterval(86_400)
            let seconds = snapshot.sessions.reduce(0.0) { total, session in
                let start = max(session.startedAt, day)
                let end = min(session.endedAt, next)
                return total + max(0, end.timeIntervalSince(start))
            }
            let label = state.range == .week
                ? day.formatted(.dateTime.weekday(.narrow))
                : day.formatted(.dateTime.day())
            return (day: day, label: label, hours: seconds / 3600)
        }
    }

    private func rankedReasons() -> [(reason: String, seconds: TimeInterval)] {
        var totals: [String: TimeInterval] = [:]
        for session in snapshot.sessions where session.endedAt >= since {
            // A session's time is shared evenly between the reasons that held it.
            guard !session.reasons.isEmpty else { continue }
            let share = session.duration / Double(session.reasons.count)
            for reason in session.reasons { totals[reason, default: 0] += share }
        }
        return totals.map { (reason: $0.key, seconds: $0.value) }.sorted { $0.seconds > $1.seconds }
    }
}
```

- [ ] **Step 2: Add the tab**

In `Sources/EyesUpApp/Dashboard/DashboardWindow.swift`:
1. Extend the enum: `case overview, triggers, processes, history, settings`.
2. Title `case .history: "History"`; symbol `case .history: "clock.arrow.trianglehead.counterclockwise.rotate.90"`.
3. Add to `DashboardState`: `let history = HistoryTabState()`.
4. In the detail switch: `case .history: HistoryTab(environment: environment, state: state.history)`.

- [ ] **Step 3: Build and look at it**

Run: `make test && make app && open build/EyesUpGuardian.app`
Expected: tests pass; the dashboard has a History tab. With a few sessions recorded it shows the per-day bars, totals, what kept the Mac awake, the session list and the sleep/wake log. With no history it says "Nothing yet in this range." and the energy tile reads "—" with "needs power readings" (or "set a rate in Settings" once watts arrive).

- [ ] **Step 4: Commit**

```bash
git add Sources/EyesUpApp
git commit -m "feat(app): add the History tab with per-day awake time, energy and sessions" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: Settings, completed

**Files:**
- Modify: `Sources/EyesUpCore/Store/AppSettings.swift` (rate, presets, heads-up lead, default policy, export/import)
- Modify: `Sources/EyesUpApp/Dashboard/SettingsTab.swift`
- Modify: `Sources/EyesUpApp/AppEnvironment.swift`, `Sources/EyesUpApp/Popover/PopoverView.swift` (use the settings instead of `Defaults`)
- Modify: `Tests/EyesUpCoreTests/SettingsTests.swift`

**Interfaces:**
- Produces:
  - `AppSettings.electricityRate: Double?` (per kWh), `presets: [TimeInterval]`, `headsUpLeadMinutes: Double`, `keepDisplayOnByDefault: Bool`
  - `AppSettings.exportData() throws -> Data`, `static func imported(from: Data) throws -> AppSettings`
  - `SettingsController.export() throws -> Data`, `importSettings(_ data: Data) throws`

- [ ] **Step 1: Write the failing tests**

Append inside `@Suite @MainActor struct SettingsTests`:
```swift
    @Test func newSettingsHaveSensibleDefaults() {
        let settings = AppSettings()
        #expect(settings.electricityRate == nil)
        #expect(settings.presets == [900, 3600, 7200, 14400])
        #expect(settings.headsUpLeadMinutes == 5)
        #expect(!settings.keepDisplayOnByDefault)
    }

    @Test func settingsValidationClampsTheNewFields() {
        #expect(AppSettings(electricityRate: -1).validated().electricityRate == nil)
        #expect(AppSettings(electricityRate: .nan).validated().electricityRate == nil)
        #expect(AppSettings(electricityRate: 99).validated().electricityRate == nil)   // no tariff is $99/kWh
        #expect(AppSettings(electricityRate: 0.32).validated().electricityRate == 0.32)

        #expect(AppSettings(presets: []).validated().presets == AppSettings().presets)
        #expect(AppSettings(presets: [0, -5, 60, 1e12]).validated().presets == [60])
        #expect(AppSettings(presets: Array(repeating: 60, count: 20)).validated().presets.count <= AppSettings.maxPresets)

        #expect(AppSettings(headsUpLeadMinutes: 0).validated().headsUpLeadMinutes == 5)
        #expect(AppSettings(headsUpLeadMinutes: 600).validated().headsUpLeadMinutes == 5)
        #expect(AppSettings(headsUpLeadMinutes: 10).validated().headsUpLeadMinutes == 10)
    }

    @Test func settingsRoundTripThroughExportAndImport() throws {
        var settings = AppSettings()
        settings.electricityRate = 0.28
        settings.presets = [600, 1800]
        settings.menuBarReadout = .timerAndPower
        let data = try settings.exportData()
        #expect(try AppSettings.imported(from: data) == settings)
    }

    @Test func importingRubbishIsRefusedAndChangesNothing() throws {
        let controller = SettingsController(store: tempStore())
        controller.update { $0.electricityRate = 0.3 }
        #expect(throws: (any Error).self) { try controller.importSettings(Data("not json".utf8)) }
        #expect(controller.settings.electricityRate == 0.3)
    }

    @Test func importingValidatesWhatItAccepts() throws {
        let controller = SettingsController(store: tempStore())
        let hostile = Data(#"{"electricityRate": 500, "headsUpLeadMinutes": 9999, "presets": []}"#.utf8)
        try controller.importSettings(hostile)
        #expect(controller.settings.electricityRate == nil)
        #expect(controller.settings.headsUpLeadMinutes == 5)
        #expect(controller.settings.presets == AppSettings().presets)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test`
Expected: FAIL to compile with `value of type 'AppSettings' has no member 'electricityRate'`.

- [ ] **Step 3: Extend the settings**

In `Sources/EyesUpCore/Store/AppSettings.swift`, add the constants, stored properties, memberwise parameters, assignments and lenient decodes:
```swift
    public static let maxPresets = 8
    public static let maxElectricityRate = 10.0
    public static let minHeadsUpLeadMinutes = 1.0
    public static let maxHeadsUpLeadMinutes = 60.0
```
```swift
    /// Money per kilowatt-hour, in the system currency. nil means "don't show money at all".
    public var electricityRate: Double?
    public var presets: [TimeInterval]
    public var headsUpLeadMinutes: Double
    public var keepDisplayOnByDefault: Bool
```
```swift
        electricityRate: Double? = nil,
        presets: [TimeInterval] = [900, 3600, 7200, 14400],
        headsUpLeadMinutes: Double = 5,
        keepDisplayOnByDefault: Bool = false
```
```swift
        self.electricityRate = electricityRate
        self.presets = presets
        self.headsUpLeadMinutes = headsUpLeadMinutes
        self.keepDisplayOnByDefault = keepDisplayOnByDefault
```
```swift
        electricityRate = try container.decodeIfPresent(Double.self, forKey: .electricityRate)
        presets = try container.decodeIfPresent([TimeInterval].self, forKey: .presets) ?? [900, 3600, 7200, 14400]
        headsUpLeadMinutes = try container.decodeIfPresent(Double.self, forKey: .headsUpLeadMinutes) ?? 5
        keepDisplayOnByDefault = try container.decodeIfPresent(Bool.self, forKey: .keepDisplayOnByDefault) ?? false
```
and in `validated()`, before `return settings`:
```swift
        if let rate = settings.electricityRate {
            let usable = rate.isFinite && rate > 0 && rate <= Self.maxElectricityRate
            settings.electricityRate = usable ? rate : nil
        }
        let usablePresets = settings.presets
            .filter { $0.isFinite && $0 >= 60 && $0 <= AwakeController.maxManualDuration }
            .sorted()
        settings.presets = usablePresets.isEmpty ? AppSettings().presets : Array(usablePresets.prefix(Self.maxPresets))
        if !settings.headsUpLeadMinutes.isFinite
            || settings.headsUpLeadMinutes < Self.minHeadsUpLeadMinutes
            || settings.headsUpLeadMinutes > Self.maxHeadsUpLeadMinutes {
            settings.headsUpLeadMinutes = 5
        }
```
Then add export/import at the end of the struct:
```swift
    /// A settings file the user can keep or move to another Mac.
    public func exportData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// Anything unreadable throws; anything out of range is clamped by `validated()`.
    public static func imported(from data: Data) throws -> AppSettings {
        try JSONDecoder().decode(AppSettings.self, from: data)
    }
```
and to `SettingsController`:
```swift
    public func export() throws -> Data {
        try settings.exportData()
    }

    public func importSettings(_ data: Data) throws {
        let imported = try AppSettings.imported(from: data)
        settings = imported.validated()
        persist()
        onChange?(settings)
    }
```

- [ ] **Step 4: Use the settings where `Defaults` was hard-coded**

In `Sources/EyesUpApp/AppEnvironment.swift`, pass the saved lead time through when settings change — inside the `settings.onChange` closure, after `SettingsApplier.apply(...)`:
```swift
            controller.setHeadsUpLead(settings.headsUpLeadMinutes * 60)
```
and add to `AwakeController` (in `Sources/EyesUpCore/AwakeController.swift`):
```swift
    /// Spec §7.3: how long before the end the heads-up appears.
    public func setHeadsUpLead(_ seconds: TimeInterval) {
        guard seconds.isFinite, seconds > 0 else { return }
        deadlines.headsUpLead = seconds
    }
```

In `Sources/EyesUpApp/Dashboard/HistoryTab.swift`, swap the placeholder for the real rate:
```swift
        return EnergyCost.money(kilowattHours, ratePerKilowattHour: environment.settings.settings.electricityRate)
            ?? "set a rate in Settings"
```

In `Sources/EyesUpApp/Popover/PopoverView.swift`, replace `Defaults.presets` with the saved list and honour the default display policy — replace the `ForEach(Defaults.presets, id: \.self)` line with:
```swift
                    ForEach(environmentSettings.presets, id: \.self) { seconds in
```
and add the stored property **immediately after `stats`**, so the memberwise initializer's order stays
`controller, onOpenDashboard, form, stats, environmentSettings, onHUDToggle` and matches the call site:
```swift
    let environmentSettings: AppSettings
```
passing `environmentSettings: environment.settings.settings` where the popover is built in
`EyesUpGuardianApp.swift`, between the `stats:` and `onHUDToggle:` arguments.

- [ ] **Step 5: Finish the Settings tab**

In `Sources/EyesUpApp/Dashboard/SettingsTab.swift`, add these sections after "Menu bar":
```swift
                    Section("Keep awake") {
                        Toggle("Keep the display on by default", isOn: Binding(
                            get: { settings.keepDisplayOnByDefault },
                            set: { on in environment.settings.update { $0.keepDisplayOnByDefault = on } }
                        ))
                        LabeledContent("Warn me before sleep") {
                            Stepper("\(Int(settings.headsUpLeadMinutes)) min", value: Binding(
                                get: { settings.headsUpLeadMinutes },
                                set: { value in environment.settings.update { $0.headsUpLeadMinutes = value } }
                            ), in: AppSettings.minHeadsUpLeadMinutes...AppSettings.maxHeadsUpLeadMinutes, step: 1)
                        }
                        LabeledContent("Quick presets") {
                            Text(settings.presets.map { TimeFormatting.duration($0) }.joined(separator: " · "))
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            ForEach([300.0, 900, 1800, 3600, 7200, 14400, 28800], id: \.self) { seconds in
                                Toggle(TimeFormatting.duration(seconds), isOn: Binding(
                                    get: { settings.presets.contains(seconds) },
                                    set: { on in
                                        environment.settings.update { current in
                                            var presets = Set(current.presets)
                                            if on { presets.insert(seconds) } else { presets.remove(seconds) }
                                            current.presets = presets.sorted()
                                        }
                                    }
                                ))
                                .toggleStyle(.button)
                                .controlSize(.small)
                            }
                        }
                    }

                    Section("Energy") {
                        LabeledContent("Electricity rate") {
                            TextField("none", value: Binding(
                                get: { settings.electricityRate },
                                set: { rate in environment.settings.update { $0.electricityRate = rate } }
                            ), format: .number.precision(.fractionLength(0...3)))
                            .frame(width: 90)
                            Text("per kWh").foregroundStyle(.secondary)
                        }
                        Text("Used only to turn the energy the Mac drew into money on the History tab. Leave it empty and the app shows kilowatt-hours only.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    Section("Your data") {
                        HStack {
                            Button("Export settings…") { exportSettings() }
                            Button("Import settings…") { importSettings() }
                            Spacer()
                            Button("Clear history", role: .destructive) { environment.history.clear() }
                        }
                        Text("Everything this app stores lives in ~/Library/Application Support/EyesUpGuardian, readable only by you.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
```
and the two file actions plus their state at the end of the view:
```swift
    private func exportSettings() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "EyesUpGuardian-settings.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try environment.settings.export().write(to: url, options: .atomic)
        } catch {
            environment.settings.reportNotice("Couldn't export settings: \(error.localizedDescription)")
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try environment.settings.importSettings(Data(contentsOf: url)) // security-allow: a file the user picked in an open panel
        } catch {
            environment.settings.reportNotice("That file isn't a settings file this app can read.")
        }
    }
```
Add `import AppKit` and `import UniformTypeIdentifiers` at the top of the file, and to `SettingsController`:
```swift
    /// Surfaces a problem in the Settings tab without throwing it away.
    public func reportNotice(_ message: String) {
        storeNotice = message
    }
```
(`storeNotice` becomes `public internal(set) var storeNotice: String?`.)

- [ ] **Step 6: Run the tests and try it**

Run: `make test && make app && open build/EyesUpGuardian.app`
Expected: the 5 new `SettingsTests` pass. In Settings: toggling presets changes the popover's buttons immediately; setting the electricity rate makes the History tab show money; Export writes a file you can re-import; Clear history empties the History tab.

- [ ] **Step 7: Commit**

```bash
git add Sources Tests
git commit -m "feat: complete Settings — presets, warning time, electricity rate, export and import" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: Launch at login

**Files:**
- Create: `Sources/EyesUpApp/Login/LaunchAtLogin.swift`, `Tests/EyesUpCoreTests/LaunchAtLoginTests.swift`
- Modify: `Sources/EyesUpCore/Store/AppSettings.swift` (`launchAtLogin`), `Sources/EyesUpApp/Dashboard/SettingsTab.swift`, `Tests/EyesUpCoreTests/SecurityGuardTests.swift`

**Interfaces:**
- Produces:
  - `protocol LoginItemService: Sendable { var isRegistered: Bool { get }; func register() throws; func unregister() throws }`
  - `struct SystemLoginItem: LoginItemService` wrapping `SMAppService.mainApp`
  - `@MainActor final class LaunchAtLogin`: `init(service:)`, `var isEnabled: Bool`, `func set(_ enabled: Bool) -> String?` (returns a message when the system refuses), `func syncFromSystem() -> Bool`
  - `AppSettings.launchAtLogin: Bool`

**The guard must be narrowed** (Plan 3's deferred item): `SMAppService.mainApp` is not escalation, but the daemon and agent forms are.

- [ ] **Step 1: Write the failing tests**

`Tests/EyesUpCoreTests/LaunchAtLoginTests.swift`:
```swift
import Foundation
import Testing
@testable import EyesUpApp
@testable import EyesUpCore

@Suite @MainActor struct LaunchAtLoginTests {
    final class FakeLoginService: LoginItemService, @unchecked Sendable {
        var registered = false
        var failure: (any Error)?
        private(set) var registerCalls = 0
        private(set) var unregisterCalls = 0

        var isRegistered: Bool { registered }

        func register() throws {
            registerCalls += 1
            if let failure { throw failure }
            registered = true
        }

        func unregister() throws {
            unregisterCalls += 1
            if let failure { throw failure }
            registered = false
        }
    }

    struct Refused: Error {}

    @Test func toggleReflectsWhatTheSystemReports() {
        let service = FakeLoginService()
        let login = LaunchAtLogin(service: service)
        #expect(!login.isEnabled)

        #expect(login.set(true) == nil)
        #expect(login.isEnabled)
        #expect(service.registerCalls == 1)

        #expect(login.set(false) == nil)
        #expect(!login.isEnabled)
        #expect(service.unregisterCalls == 1)
    }

    @Test func aRefusedRegistrationIsReported() {
        let service = FakeLoginService()
        service.failure = Refused()
        let login = LaunchAtLogin(service: service)
        let message = login.set(true)
        #expect(message != nil)
        #expect(!login.isEnabled) // never claims success it didn't get
    }

    @Test func theSystemIsTheSourceOfTruth() {
        // The user can turn it off in System Settings; the app must follow, not insist.
        let service = FakeLoginService()
        let login = LaunchAtLogin(service: service)
        _ = login.set(true)
        service.registered = false
        #expect(!login.syncFromSystem())
        #expect(!login.isEnabled)
    }
}
```

Append inside `@Suite struct SecurityGuardTests`'s `guardDetectsViolations`:
```swift
        // Launch at login is allowed; daemons and agents are not.
        #expect(try Self.violations(in: "SMAppService.mainApp.register()").isEmpty)
        #expect(try Self.violations(in: "SMAppService.daemon(plistName: p)") == ["privilege escalation"])
        #expect(try Self.violations(in: "SMAppService.agent(plistName: p)") == ["privilege escalation"])
        #expect(try Self.violations(in: "SMAppService.loginItem(identifier: id)") == ["privilege escalation"])
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test`
Expected: FAIL to compile with `cannot find type 'LoginItemService' in scope`, plus `guardDetectsViolations` failing on the `mainApp` line.

- [ ] **Step 3: Narrow the guard**

In `Tests/EyesUpCoreTests/SecurityGuardTests.swift`, replace the privilege-escalation rule:
```swift
        (#"\bset(res|re|r|e)?[ug]id\b|\b(SMAppService|SMLoginItemSetEnabled)\b"#, "privilege escalation"),
```
with:
```swift
        // SMAppService.mainApp is just "open me at login"; the daemon/agent/loginItem forms install
        // something that runs on its own, which this app never does.
        (#"\bset(res|re|r|e)?[ug]id\b|SMAppService\.(daemon|agent|loginItem)\s*\(|\bSMLoginItemSetEnabled\b"#, "privilege escalation"),
```

- [ ] **Step 4: Write launch at login**

`Sources/EyesUpApp/Login/LaunchAtLogin.swift`:
```swift
import Foundation
import ServiceManagement

/// Registering the app itself to open at login. Behind a protocol so tests never touch the real
/// login-item database.
public protocol LoginItemService: Sendable {
    var isRegistered: Bool { get }
    func register() throws
    func unregister() throws
}

/// `SMAppService.mainApp` opens *this app* at login. It installs no daemon and no agent, needs no
/// admin rights, and the user can override it in System Settings — which is why the system, not this
/// app, is the source of truth.
public struct SystemLoginItem: LoginItemService {
    public init() {}

    public var isRegistered: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public func register() throws {
        try SMAppService.mainApp.register()
    }

    public func unregister() throws {
        try SMAppService.mainApp.unregister()
    }
}

@MainActor
@Observable
public final class LaunchAtLogin {
    public private(set) var isEnabled: Bool

    @ObservationIgnored private let service: any LoginItemService

    public init(service: any LoginItemService = SystemLoginItem()) {
        self.service = service
        isEnabled = service.isRegistered
    }

    /// Returns nil on success, or a message to show when macOS refuses.
    @discardableResult
    public func set(_ enabled: Bool) -> String? {
        do {
            if enabled { try service.register() } else { try service.unregister() }
            isEnabled = service.isRegistered
            return isEnabled == enabled ? nil : "macOS didn't apply that. Check Login Items in System Settings."
        } catch {
            isEnabled = service.isRegistered
            return "macOS refused: \(error.localizedDescription). An app built from source has to be in /Applications for this to work."
        }
    }

    /// The user may have changed it in System Settings; believe the system.
    @discardableResult
    public func syncFromSystem() -> Bool {
        isEnabled = service.isRegistered
        return isEnabled
    }
}
```

- [ ] **Step 5: Put it in Settings**

Add `launchAtLogin` to `AppSettings` (stored property, parameter `launchAtLogin: Bool = false`, assignment, and `try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false`) so the intent is remembered, then in `SettingsTab.swift` add to the "Keep awake" section:
```swift
                        Toggle("Open EyesUpGuardian at login", isOn: Binding(
                            get: { environment.launchAtLogin.isEnabled },
                            set: { on in
                                if let message = environment.launchAtLogin.set(on) {
                                    environment.settings.reportNotice(message)
                                } else {
                                    environment.settings.update { $0.launchAtLogin = on }
                                }
                            }
                        ))
```
and in `AppEnvironment`:
```swift
    let launchAtLogin = LaunchAtLogin()
```
with `launchAtLogin.syncFromSystem()` called in `start()`.

- [ ] **Step 6: Run the tests and try it for real**

Run: `make test`
Expected: the 3 `LaunchAtLoginTests` and the 4 new guard cases pass.
Run: `make install && open /Applications/EyesUpGuardian.app`, then in Settings turn **Open EyesUpGuardian at login** on.
Expected: the toggle stays on, and the app appears in System Settings → General → Login Items. Turning it off there and reopening the dashboard shows the toggle off (the system wins). If registration is refused, the message says so instead of the toggle lying.

- [ ] **Step 7: Commit**

```bash
git add Sources Tests
git commit -m "feat(app): add launch at login, with the system as the source of truth" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 7: Global shortcut and tab keys

**Files:**
- Create: `Sources/EyesUpApp/HotKey/GlobalHotKey.swift`, `Tests/EyesUpCoreTests/HotKeyTests.swift`
- Modify: `Sources/EyesUpCore/Store/AppSettings.swift` (`globalShortcutEnabled`), `Sources/EyesUpApp/Dashboard/SettingsTab.swift`, `Sources/EyesUpApp/Dashboard/DashboardWindow.swift` (⌘1–⌘5), `Sources/EyesUpApp/EyesUpGuardianApp.swift`

**Interfaces:**
- Produces:
  - `protocol HotKeyRegistering: AnyObject { func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping @MainActor () -> Void) -> Bool; func unregister() }`
  - `final class CarbonHotKey: HotKeyRegistering` — ⌃⌥⌘E by default (`keyCode 14`, modifiers 6400)
  - `@MainActor @Observable final class GlobalShortcut`: `init(registrar:)`, `isActive`, `lastError`, `func apply(enabled: Bool, action: @escaping @MainActor () -> Void)`
  - `AppSettings.globalShortcutEnabled: Bool` (default true)

Carbon hot keys need no Accessibility permission; an event tap would, and could read every keystroke. This app will never ask for that.

- [ ] **Step 1: Write the failing tests**

`Tests/EyesUpCoreTests/HotKeyTests.swift`:
```swift
import Foundation
import Testing
@testable import EyesUpApp

@Suite @MainActor struct HotKeyTests {
    final class FakeRegistrar: HotKeyRegistering {
        var succeeds = true
        private(set) var registrations = 0
        private(set) var unregistrations = 0
        private var handler: (@MainActor () -> Void)?

        func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping @MainActor () -> Void) -> Bool {
            registrations += 1
            guard succeeds else { return false }
            self.handler = handler
            return true
        }

        func unregister() {
            unregistrations += 1
            handler = nil
        }

        func press() { handler?() }
    }

    @Test func enablingRegistersAndPressingFires() {
        let registrar = FakeRegistrar()
        let shortcut = GlobalShortcut(registrar: registrar)
        var fired = 0
        shortcut.apply(enabled: true) { fired += 1 }
        #expect(shortcut.isActive)
        registrar.press()
        #expect(fired == 1)
    }

    @Test func disablingTheShortcutUnregistersIt() {
        let registrar = FakeRegistrar()
        let shortcut = GlobalShortcut(registrar: registrar)
        shortcut.apply(enabled: true) {}
        shortcut.apply(enabled: false) {}
        #expect(!shortcut.isActive)
        #expect(registrar.unregistrations == 1)
    }

    @Test func aRefusedHotKeyIsReported() {
        // Another app already owns this combination.
        let registrar = FakeRegistrar()
        registrar.succeeds = false
        let shortcut = GlobalShortcut(registrar: registrar)
        shortcut.apply(enabled: true) {}
        #expect(!shortcut.isActive)
        #expect(shortcut.lastError != nil)
    }

    @Test func applyingTwiceDoesNotStackRegistrations() {
        let registrar = FakeRegistrar()
        let shortcut = GlobalShortcut(registrar: registrar)
        shortcut.apply(enabled: true) {}
        shortcut.apply(enabled: true) {}
        #expect(registrar.registrations == 1)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test`
Expected: FAIL to compile with `cannot find type 'HotKeyRegistering' in scope`.

- [ ] **Step 3: Write the hot key**

`Sources/EyesUpApp/HotKey/GlobalHotKey.swift`:
```swift
import AppKit
import Carbon.HIToolbox
import Observation

public protocol HotKeyRegistering: AnyObject {
    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping @MainActor () -> Void) -> Bool
    func unregister()
}

/// Carries the handler across the C callback boundary.
private final class HotKeyBox: @unchecked Sendable {
    let handler: @MainActor () -> Void

    init(_ handler: @escaping @MainActor () -> Void) {
        self.handler = handler
    }

    func fire() {
        DispatchQueue.main.async { MainActor.assumeIsolated { self.handler() } }
    }
}

/// One shared function pointer: Carbon matches handlers by pointer when removing them.
private let hotKeyCallback: EventHandlerUPP = { _, _, context in
    guard let context else { return noErr }
    Unmanaged<HotKeyBox>.fromOpaque(context).takeUnretainedValue().fire()
    return noErr
}

/// A system-wide shortcut through Carbon, which needs no Accessibility permission — unlike an event
/// tap, which could read every keystroke the user types.
@MainActor
public final class CarbonHotKey: HotKeyRegistering {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var box: HotKeyBox?

    public init() {}

    public func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping @MainActor () -> Void) -> Bool {
        unregister()
        let box = HotKeyBox(handler)
        self.box = box

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        guard InstallEventHandler(GetApplicationEventTarget(), hotKeyCallback, 1, &spec,
                                  Unmanaged.passUnretained(box).toOpaque(), &handlerRef) == noErr else {
            self.box = nil
            return false
        }
        let id = EventHotKeyID(signature: OSType(0x45_59_45_53), id: 1) // "EYES"
        let status = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard status == noErr, hotKeyRef != nil else {
            unregister()
            return false
        }
        return true
    }

    public func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        if let handlerRef { RemoveEventHandler(handlerRef) }
        handlerRef = nil
        box = nil
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}

@MainActor
@Observable
public final class GlobalShortcut {
    /// ⌃⌥⌘E — E for EyesUp.
    public static let keyCode: UInt32 = 14
    public static let modifiers = UInt32(controlKey | optionKey | cmdKey)
    public static let description = "⌃⌥⌘E"

    public private(set) var isActive = false
    public private(set) var lastError: String?

    @ObservationIgnored private let registrar: any HotKeyRegistering

    public init(registrar: any HotKeyRegistering = CarbonHotKey()) {
        self.registrar = registrar
    }

    public func apply(enabled: Bool, action: @escaping @MainActor () -> Void) {
        guard enabled != isActive else { return }
        guard enabled else {
            registrar.unregister()
            isActive = false
            lastError = nil
            return
        }
        if registrar.register(keyCode: Self.keyCode, modifiers: Self.modifiers, handler: action) {
            isActive = true
            lastError = nil
        } else {
            isActive = false
            lastError = "\(Self.description) is already taken by another app, so the shortcut is off."
        }
    }
}
```

- [ ] **Step 4: Wire it up, and add the tab keys**

In `Sources/EyesUpCore/Store/AppSettings.swift`, add `globalShortcutEnabled: Bool` (default `true`, lenient decode `?? true`).

In `Sources/EyesUpApp/EyesUpGuardianApp.swift`, add a property and apply it at launch and on settings changes:
```swift
    private let shortcut = GlobalShortcut()
```
```swift
        shortcut.apply(enabled: environment.settings.settings.globalShortcutEnabled) { [weak statusItem] in
            _ = statusItem // keep the item alive
            environment.controller.isAwake
                ? environment.controller.stopAll()
                : environment.controller.startIndefinite(policy: environment.controller.currentPolicy)
        }
```
inside the existing `environment.onSettingsChanged` closure, also re-apply:
```swift
            self?.shortcut.apply(enabled: settings.globalShortcutEnabled) { … same action … }
```
Extract that action into a small private method on `AppDelegate` so both call sites use it:
```swift
    private func toggleKeepAwake(_ environment: AppEnvironment) {
        environment.controller.isAwake
            ? environment.controller.stopAll()
            : environment.controller.startIndefinite(policy: environment.controller.currentPolicy)
    }
```

In `Sources/EyesUpApp/Dashboard/SettingsTab.swift`, add to "Keep awake":
```swift
                        Toggle("Global shortcut (\(GlobalShortcut.description))", isOn: Binding(
                            get: { settings.globalShortcutEnabled },
                            set: { on in environment.settings.update { $0.globalShortcutEnabled = on } }
                        ))
                        Text("Turns keeping awake on or off from anywhere. It needs no accessibility permission — this app never reads your keystrokes.")
                            .font(.caption).foregroundStyle(.secondary)
```

In `Sources/EyesUpApp/Dashboard/DashboardWindow.swift`, give the sidebar rows ⌘1–⌘5 (spec §7.3) by adding to each row in the `List`:
```swift
                Label(tab.title, systemImage: tab.symbol)
                    .tag(tab)
                    .keyboardShortcut(tab.shortcut, modifiers: .command)
```
and to the `Tab` enum:
```swift
        /// ⌘1–⌘5, in sidebar order.
        var shortcut: KeyEquivalent {
            switch self {
            case .overview: "1"
            case .triggers: "2"
            case .processes: "3"
            case .history: "4"
            case .settings: "5"
            }
        }
```

- [ ] **Step 5: Run the tests and try the shortcut**

Run: `make test && make app && open build/EyesUpGuardian.app`
Expected: the 4 `HotKeyTests` pass.
Press **⌃⌥⌘E** with any app focused.
Expected: the menu-bar ring fills (keeping awake with no end time); press again and it empties. Confirm with `pmset -g assertions | grep EyesUpGuardian`.
In the dashboard, press ⌘1 through ⌘5.
Expected: the tabs switch. Turn the shortcut off in Settings; ⌃⌥⌘E then does nothing.

- [ ] **Step 6: Commit**

```bash
git add Sources Tests
git commit -m "feat(app): add the ⌃⌥⌘E global shortcut and ⌘1–⌘5 tab keys" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 8: HUD polish

**Files:**
- Modify: `Sources/EyesUpApp/HUD/HUDWindow.swift` (corner snapping, hover fade, click-through), `Sources/EyesUpCore/Store/AppSettings.swift` (`hudClickThrough`), `Sources/EyesUpApp/Dashboard/SettingsTab.swift`, `Sources/EyesUpApp/MenuBar/StatusItemController.swift` (menu item reflects state)
- Modify: `Tests/EyesUpCoreTests/SettingsTests.swift`

Spec §7.4 asks for four things the HUD doesn't do yet: snap to a corner, fade when the mouse is away, optional click-through, and a ring glyph. The doc comment currently admits they're missing; this task makes it true instead.

**Interfaces:**
- Produces: `HUDWindowController.snapToNearestCorner()`, `AppSettings.hudClickThrough: Bool`, `HUDPosition.snapped(in:size:margin:)`, `StatusItemController.onIsHUDPinned`.

- [ ] **Step 1: Write the failing test**

Append inside `@Suite @MainActor struct SettingsTests`:
```swift
    @Test func hudPositionsSnapToTheNearestCorner() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let size = CGSize(width: 200, height: 60)
        // Near the top-left, with a 20 pt margin.
        #expect(HUDPosition(x: 60, y: 700).snapped(in: screen, size: size, margin: 20) == HUDPosition(x: 20, y: 720))
        // Near the bottom-right.
        #expect(HUDPosition(x: 900, y: 40).snapped(in: screen, size: size, margin: 20) == HUDPosition(x: 780, y: 20))
        // Dead centre still lands in a corner rather than floating.
        let centred = HUDPosition(x: 400, y: 370).snapped(in: screen, size: size, margin: 20)
        #expect([20.0, 780.0].contains(centred.x))
        #expect([20.0, 720.0].contains(centred.y))
    }

    @Test func clickThroughDefaultsToOff() {
        #expect(!AppSettings().hudClickThrough)
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `make test`
Expected: FAIL to compile with `value of type 'HUDPosition' has no member 'snapped'`.

- [ ] **Step 3: Add snapping and the setting**

In `Sources/EyesUpCore/Store/AppSettings.swift`, extend `HUDPosition`:
```swift
extension HUDPosition {
    /// Pulls the panel to whichever corner it is closest to, so it always sits somewhere deliberate.
    public func snapped(in screen: CGRect, size: CGSize, margin: Double) -> HUDPosition {
        let left = Double(screen.minX) + margin
        let right = Double(screen.maxX) - Double(size.width) - margin
        let bottom = Double(screen.minY) + margin
        let top = Double(screen.maxY) - Double(size.height) - margin
        let centreX = x + Double(size.width) / 2
        let centreY = y + Double(size.height) / 2
        return HUDPosition(
            x: centreX < Double(screen.midX) ? left : right,
            y: centreY < Double(screen.midY) ? bottom : top
        )
    }
}
```
and add `hudClickThrough: Bool` (default `false`, lenient decode `?? false`).

- [ ] **Step 4: Make the HUD behave**

In `Sources/EyesUpApp/HUD/HUDWindow.swift`:

1. Replace the stale doc comment at the top of `HUDView` with:
```swift
/// The pinnable mini panel (spec §7.4): a draining ring, the countdown and a compact stat line, on
/// every Space. It fades when the pointer is elsewhere and snaps to the nearest corner when dragged.
```
2. Add the ring and the fade to `HUDView`. Give it a hover state object (no `@State`):
```swift
@MainActor
@Observable
final class HUDHoverState {
    var isHovering = false
}
```
and in `HUDView`, take `@Bindable var hover: HUDHoverState`, wrap the panel with:
```swift
        .opacity(hover.isHovering ? 1 : 0.4)
        .animation(.easeInOut(duration: 0.2), value: hover.isHovering)
        .onHover { hover.isHovering = $0 }
```
3. Draw the ring beside the countdown, reusing the menu-bar glyph:
```swift
            Image(nsImage: RingIcon.image(active: controller.isAwake, fraction: ringFraction(now: now)))
                .renderingMode(.template)
                .foregroundStyle(controller.isAwake ? .orange : .secondary)
```
with:
```swift
    private func ringFraction(now: Date) -> Double? {
        guard let until = controller.awakeUntil, let start = controller.sessionStart else { return nil }
        return TimeFormatting.remainingFraction(now: now, start: start, end: until)
    }
```
(and drop the old `Image(systemName:)`).
4. In `HUDWindowController`, snap on drag-end and honour click-through:
```swift
    /// Called when the panel stops moving, and when it is first shown.
    func snapToNearestCorner() {
        guard let panel, let screen = panel.screen ?? NSScreen.main else { return }
        let current = HUDPosition(x: Double(panel.frame.origin.x), y: Double(panel.frame.origin.y))
        let snapped = current.snapped(in: screen.visibleFrame, size: panel.frame.size, margin: 20)
        panel.setFrameOrigin(NSPoint(x: snapped.x, y: snapped.y))
        environment.settings.update { $0.hudPosition = snapped }
    }

    func applyClickThrough(_ enabled: Bool) {
        panel?.ignoresMouseEvents = enabled
    }
```
and in `show()`, after `place(panel)`:
```swift
        panel.ignoresMouseEvents = environment.settings.settings.hudClickThrough
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.snapToNearestCorner() }
        }
```
with a stored `private var moveObserver: NSObjectProtocol?` removed in `hide()`.
5. In `Sources/EyesUpApp/Dashboard/SettingsTab.swift`, add a HUD section:
```swift
                    Section("Floating HUD") {
                        Toggle("Show the HUD", isOn: Binding(
                            get: { settings.hudVisible },
                            set: { on in environment.onToggleHUD?(on) }
                        ))
                        Toggle("Let clicks pass through it", isOn: Binding(
                            get: { settings.hudClickThrough },
                            set: { on in environment.settings.update { $0.hudClickThrough = on } }
                        ))
                        Text("The HUD floats above other apps and snaps to the nearest corner when you drag it.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
```
with `var onToggleHUD: ((Bool) -> Void)?` on `AppEnvironment`, set by the app delegate to `{ $0 ? hud.show() : hud.hide() }`, and the delegate calling `hud.applyClickThrough(settings.hudClickThrough)` from `onSettingsChanged`.
6. In `Sources/EyesUpApp/MenuBar/StatusItemController.swift`, make the menu item honest (Plan 3's deferred item): add `var onIsHUDPinned: (() -> Bool)?` and use it:
```swift
        menu.addItem(menuItem(onIsHUDPinned?() == true ? "Unpin HUD" : "Pin HUD", #selector(toggleHUD)))
```
set by the delegate to `{ hud.isVisible }`.

- [ ] **Step 5: Run the tests and try it**

Run: `make test && make app && open build/EyesUpGuardian.app`
Expected: the 2 new settings tests pass. Then:

| Action | Expected |
|---|---|
| Pin the HUD, drag it near the middle-left | It snaps to the nearest corner when you let go |
| Move the pointer away | It fades to 40%; hovering brings it back |
| Start a 5-minute timer | The ring in the HUD drains like the menu-bar one |
| Settings → "Let clicks pass through it" | Clicks land on the window behind the HUD |
| Right-click the menu-bar icon while pinned | The item reads **Unpin HUD** |
| Quit and relaunch | It reappears in the same corner |

- [ ] **Step 6: Commit**

```bash
git add Sources Tests
git commit -m "feat(app): HUD snaps to corners, fades when idle, and can pass clicks through" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 9: The rest of the menu-bar readout options

**Files:**
- Modify: `Sources/EyesUpCore/Store/AppSettings.swift` (`MenuBarReadout` cases), `Sources/EyesUpApp/Stats/StatsViewModel.swift` (`readoutText`), `Tests/EyesUpCoreTests/SettingsTests.swift`, `Tests/EyesUpAppTests/StatViewModelTests.swift`

Spec §7.1 lists CPU, RAM, watts, temperature and network as readout choices; Plan 3 shipped CPU and watts. This adds the rest.

- [ ] **Step 1: Write the failing tests**

Append inside `SettingsTests`:
```swift
    @Test func everyReadoutNamesTheMetricsItNeeds() {
        #expect(MenuBarReadout.timerAndMemory.metricIDs == [.memory])
        #expect(MenuBarReadout.timerAndTemperature.metricIDs == [.temperature])
        #expect(MenuBarReadout.timerAndNetwork.metricIDs == [.network])
        // Every case must name its metrics, or it would display a stat nothing sampled.
        for readout in MenuBarReadout.allCases where readout != .iconOnly && readout != .timer {
            #expect(!readout.metricIDs.isEmpty, "\(readout) shows a stat but subscribes to nothing")
        }
    }
```

Append inside `StatViewModelTests`:
```swift
    @Test func readoutTextCoversEveryChoice() {
        let center = makeCenter()
        let model = StatsViewModel(center: center, ids: [.cpu, .memory, .power, .temperature, .network], interval: 2)
        model.start()
        #expect(model.readoutText(for: .timerAndMemory).contains("GB"))
        #expect(model.readoutText(for: .timerAndTemperature) == StatFormatting.unavailable || model.readoutText(for: .timerAndTemperature).contains("°C"))
        model.stop()
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test`
Expected: FAIL to compile with `type 'MenuBarReadout' has no member 'timerAndMemory'`.

- [ ] **Step 3: Add the cases**

In `Sources/EyesUpCore/Store/AppSettings.swift`, extend the enum:
```swift
    case iconOnly, timer, timerAndCPU, timerAndMemory, timerAndPower, timerAndTemperature, timerAndNetwork, timerCPUAndPower
```
with titles ("Icon, time and memory", "Icon, time and temperature", "Icon, time and network") and:
```swift
        case .timerAndMemory: [.memory]
        case .timerAndTemperature: [.temperature]
        case .timerAndNetwork: [.network]
```

In `Sources/EyesUpApp/Stats/StatsViewModel.swift`, extend `readoutText`:
```swift
        if readout.metricIDs.contains(.memory), let memory = snapshot.memory {
            parts.append(StatFormatting.bytes(memory.usedBytes))
        }
        if readout.metricIDs.contains(.temperature), let temperature = snapshot.temperature {
            parts.append(StatFormatting.celsius(temperature.celsius))
        }
        if readout.metricIDs.contains(.network), let network = snapshot.network {
            parts.append("↓" + StatFormatting.rate(network.inBytesPerSecond))
        }
```
and when nothing is readable, return `StatFormatting.unavailable` rather than an empty string for a readout that promised a stat:
```swift
        if parts.isEmpty && !readout.metricIDs.isEmpty { return StatFormatting.unavailable }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `make test`
Expected: the 2 new tests pass along with everything else.

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "feat(app): add memory, temperature and network to the menu-bar readout" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 10: Pay off the deferred list — the parts a person notices

**Files:**
- Modify: `Sources/EyesUpApp/Popover/PopoverView.swift`, `Sources/EyesUpApp/MenuBar/StatusItemController.swift`, `Sources/EyesUpApp/Dashboard/ProcessesTab.swift`, `Sources/EyesUpApp/Dashboard/TriggerEditorSheet.swift`, `Sources/EyesUpCore/AwakeController.swift`, `Sources/EyesUpCore/Holds/DurationParser.swift`, `Sources/EyesUpCore/Triggers/TriggerEngine.swift`, `Sources/EyesUpCore/Store/AppSettings.swift`
- Modify: `Tests/EyesUpCoreTests/DurationParserTests.swift`, `AwakeControllerTests.swift`, `TriggerEngineTests.swift`, `SettingsTests.swift`

Six items carried since Plan 1, each user-visible:
1. **"1h 30m" is rejected** although the app writes durations that way itself.
2. **A pasted PID with a trailing newline** is rejected.
3. **Watching another user's process** says "No running process has that ID", which is wrong.
4. **Paused triggers are invisible** outside the dashboard.
5. **Notices never clear** once shown.
6. **The trigger editor can't change a trigger's type** after it's created.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/EyesUpCoreTests/DurationParserTests.swift`:
```swift
    @Test(arguments: ["1h 30m", " 2h 15m ", "1h  5m"])
    func acceptsTheSpacedFormTheAppItselfPrints(text: String) {
        #expect(DurationParser.parse(text) != nil)
    }

    @Test func stillRejectsTheThingsItShould() {
        #expect(DurationParser.parse("1h 30") == nil)
        #expect(DurationParser.parse("h m") == nil)
        #expect(DurationParser.parse("1 h 30 m") == nil)
    }
```

Append inside `AwakeControllerTests`:
```swift
    @Test func parsePIDAcceptsAPastedValueWithANewline() throws {
        #expect(try AwakeController.parsePID("48213\n") == 48213)
        #expect(try AwakeController.parsePID(" 48213 \n") == 48213)
    }

    @Test func watchingAnotherUsersProcessSaysSo() {
        let identity = ProcessIdentity(pid: 99, startTime: 1)
        inspector.identities[99] = identity
        inspector.owners[99] = 0 // root
        let controller = makeController()
        #expect(throws: AwakeError.notYourProcess) { try controller.watchProcess(pid: 99, policy: .system) }
    }
```

Append inside `TriggerEngineTests`:
```swift
    @Test func noticesCanBeCleared() throws {
        let store = tempStore()
        try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("nonsense".utf8).write(to: store.url)
        let engine = makeEngine(controller: makeController(), store: store)
        engine.load()
        #expect(engine.storeNotice != nil)
        engine.clearNotice()
        #expect(engine.storeNotice == nil)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test`
Expected: FAIL — the spaced durations return nil, `parsePID` throws on the newline, `notYourProcess` doesn't exist, `clearNotice` doesn't exist.

- [ ] **Step 3: Fix the core ones**

`Sources/EyesUpCore/Holds/DurationParser.swift` — accept one optional space between the parts, since the app prints "1h 30m":
```swift
        let pattern = /(?:(\d{1,3})h)?\s{0,2}(?:(\d{1,4})m)?/.asciiOnlyDigits()
```

`Sources/EyesUpCore/AwakeController.swift`:
```swift
    case notYourProcess
```
with the message:
```swift
        case .notYourProcess: "That process belongs to another user, so EyesUpGuardian can't watch it."
```
in `parsePID`, trim newlines too:
```swift
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
```
and in `watchProcess`, tell the truth about why:
```swift
        guard let identity = inspector.identity(of: pid) else {
            // libproc refuses another user's process, which is different from there being none.
            throw ProcessControl.processExists(pid) ? AwakeError.notYourProcess : AwakeError.noSuchProcess
        }
```
with, in `Sources/EyesUpCore/Processes/ProcessControl.swift`:
```swift
    /// True when a process with this PID exists, whoever owns it.
    public static func processExists(_ pid: Int32) -> Bool {
        // Signal 0 sends nothing; it only asks whether the process exists. EPERM means it exists
        // and belongs to someone else, which is exactly what the caller needs to distinguish.
        pid > 0 && (kill(pid, 0) == 0 || errno == EPERM)
    }
```

`Sources/EyesUpCore/Triggers/TriggerEngine.swift`, plus the same three lines on `AwakeController` and `SettingsController` and `HistoryController`:
```swift
    /// Notices are dismissible: one bad launch shouldn't leave a permanent banner.
    public func clearNotice() {
        storeNotice = nil
    }
```

- [ ] **Step 4: Fix the ones in the UI**

`Sources/EyesUpApp/Popover/PopoverView.swift` — show the paused state and let notices be dismissed:
```swift
    @ViewBuilder
    private var pausedBadge: some View {
        if environmentIsPaused {
            Label("Triggers paused", systemImage: "pause.circle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }
```
added to the body under the header, with `let environmentIsPaused: Bool` passed in from the delegate, and every notice row gaining a dismiss button:
```swift
        if let notice = controller.storeNotice {
            HStack {
                Label(notice, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Dismiss") { controller.clearNotice() }.buttonStyle(.plain).font(.caption2)
            }
        }
```

`Sources/EyesUpApp/MenuBar/StatusItemController.swift` — say it in the tooltip too:
```swift
        let toolTip = controller.isAwake
            ? "EyesUpGuardian: " + controller.holds.map(\.label).joined(separator: ", ")
            : "EyesUpGuardian: your Mac may sleep"
```
becomes:
```swift
        var toolTip = controller.isAwake
            ? "EyesUpGuardian: " + controller.holds.map(\.label).joined(separator: ", ")
            : "EyesUpGuardian: your Mac may sleep"
        if onIsPaused?() == true { toolTip += " · triggers paused" }
```
with `var onIsPaused: (() -> Bool)?` set by the delegate to `{ environment.engine.isPaused }`.

`Sources/EyesUpApp/Dashboard/ProcessesTab.swift` — count what is shown:
```swift
    private var summary: String {
        let shown = entries
        let threads = shown.reduce(0) { $0 + $1.threads }
```

`Sources/EyesUpApp/Dashboard/TriggerEditorSheet.swift` — allow changing the type while editing, since the engine already supports it:
```swift
                Picker("Keep awake", selection: $draft.kind) {
                    ForEach(TriggerDraft.Kind.allCases) { kind in Text(kind.title).tag(kind) }
                }
```
(delete the `.disabled(!draft.isNew)` line).

- [ ] **Step 5: Run the tests and check the app**

Run: `make test && make app`
Expected: every new test passes and the build is clean.
Open the popover with triggers paused: it shows **Triggers paused**. Type `1h 30m` into Custom…: it starts a 90-minute timer. Try watching a root process (`pgrep -x launchd`): the message says it belongs to another user.

- [ ] **Step 6: Commit**

```bash
git add Sources Tests
git commit -m "fix: accept spaced durations, explain root processes, surface paused triggers, dismiss notices" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 11: Pay off the deferred list — the parts that cost resources

**Files:**
- Modify: `Sources/EyesUpCore/Metrics/Probes/LiveProbes.swift` (lazy SMC), `Sources/EyesUpCore/Metrics/Probes/StorageProbe.swift` + `Sources/EyesUpCore/Triggers/SystemSources.swift` + `Sources/EyesUpCore/System/LiveSystemSources.swift` (one disk walk), `Sources/EyesUpCore/Metrics/MetricsCenter.swift` (reset off the main actor), `Sources/EyesUpCore/Store/JSONFileStore.swift` (unique corrupt names)
- Modify: `Tests/EyesUpCoreTests/StoreTests.swift`, `Tests/EyesUpCoreTests/MetricsCenterTests.swift`

Four carried items, none user-visible but all real:
1. The AppleSMC connection opens at launch even when nothing samples it.
2. `StorageProbe` walks the IOKit disk tree twice per sample and reads the two counters at different instants.
3. `MetricsCenter.refresh()` takes the probe lock on the main actor, so a wake can stall the UI for the length of a sample.
4. Two corrupt files in the same second collide, and the loser is deleted.

- [ ] **Step 1: Write the failing tests**

Append inside `StoreTests`:
```swift
    @Test func twoCorruptFilesInTheSameSecondBothSurvive() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("nonsense".utf8).write(to: url)
        _ = store.load(now: referenceDate)
        try Data("more nonsense".utf8).write(to: url)
        _ = store.load(now: referenceDate) // same instant
        let copies = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.contains(".corrupt-") }
        #expect(copies.count == 2)
    }
```

Append inside `MetricsCenterTests`:
```swift
    @Test func refreshDoesNotSampleOnTheMainActor() {
        // resetBaselines takes the probe lock; doing that inline on the main actor lets a wake stall the UI.
        let center = makeCenter()
        let subscription = center.subscribe([.network], interval: 1)
        probes.resetDelay = 0.05
        let start = ContinuousClock.now
        center.refresh()
        let elapsed = Double((ContinuousClock.now - start).components.attoseconds) / 1e18
        #expect(elapsed < 0.04, "refresh blocked the main actor for \(elapsed)s")
        subscription.cancel()
    }
```
with `var resetDelay: TimeInterval = 0` on `FakeProbes`, and its `resetBaselines()` sleeping that long.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test`
Expected: the corrupt-name test finds 1 file, and the refresh test reports a blocked main actor.

- [ ] **Step 3: Apply the four fixes**

`Sources/EyesUpCore/Store/JSONFileStore.swift` — make the name unique:
```swift
        let target = url.deletingLastPathComponent()
            .appendingPathComponent("\(stem).corrupt-\(Int(now.timeIntervalSince1970))-\(UUID().uuidString.prefix(4)).json")
```

`Sources/EyesUpCore/Metrics/Probes/LiveProbes.swift` — open the SMC on first use:
```swift
    /// Opened the first time something asks for power, fans or temperature, so the default
    /// configuration holds no IOKit user client at all.
    private var smcProbe: SMCProbe?
    private var triedSMC = false

    private func smc() -> SMCProbe? {
        if !triedSMC {
            triedSMC = true
            smcProbe = SMC().map { SMCProbe(smc: $0) }
        }
        return smcProbe
    }
```
with the three call sites becoming `smc()?.power()`, `smc()?.fans()`, `smc()?.temperature()`, and the `smc` stored property removed from `init`.

`Sources/EyesUpCore/Triggers/SystemSources.swift` — one reading, both numbers:
```swift
    /// Bytes read and written together, from one pass over the disk drivers.
    func diskBytes() -> (read: UInt64, written: UInt64)?
```
with a default implementation returning `nil`, `LiveSystemCounters.diskBytes()` exposing the existing private `blockStorageBytes()`, and `StorageProbe.sample()` using it:
```swift
        let disk = counters.diskBytes()
        let read = disk.flatMap { readMeter.rate(for: $0.read, at: now) }
        let write = disk.flatMap { writeMeter.rate(for: $0.written, at: now) }
```

`Sources/EyesUpCore/Metrics/MetricsCenter.swift` — reset where sampling happens:
```swift
    public func refresh() {
        histories.removeAll()
        let probes = probes
        executor.run({
            probes.resetBaselines()
            return MetricsSnapshot()
        }) { _ in }
        sampleNow()
    }
```

- [ ] **Step 4: Run the tests and re-measure**

Run: `make test && make test-integration`
Expected: everything passes, including the two new tests.
Run: `make perf`
Expected: **PASS**, and the idle configuration now opens no SMC connection — confirm with:
```bash
open build/EyesUpGuardian.app && sleep 5
lsof -nP -p "$(pgrep -nx EyesUpGuardian)" | grep -ci applesmc
osascript -e 'tell application id "dev.eyesupguardian.EyesUpGuardian" to quit'
```
Expected: `0` with the default readout.

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "perf: open the SMC lazily, read disk counters once, reset baselines off the main actor" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 12: App icon and About

**Files:**
- Create: `Scripts/make-icon.swift`, `Sources/EyesUpApp/Resources/AppIcon.icns` (generated, committed), `Sources/EyesUpApp/About/AboutWindow.swift`
- Modify: `Sources/EyesUpApp/Resources/Info.plist`, `Scripts/bundle.sh`, `Makefile`, `Sources/EyesUpApp/MenuBar/StatusItemController.swift` (About menu item)

The icon is generated by a script rather than drawn by hand, so it can be regenerated and reviewed as code. The drawing is the app's own ring: an amber arc on a dark rounded square.

- [ ] **Step 1: Write the icon generator**

`Scripts/make-icon.swift`:
```swift
// Draws the app icon at every size macOS wants and writes an .icns.
// Run with: make icon   (needs iconutil, which ships with macOS)
import AppKit
import CoreGraphics
import Foundation

let iconSizes = [16, 32, 64, 128, 256, 512, 1024]

func drawIcon(size: Int) -> Data? {
    let side = CGFloat(size)
    let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
        // Dark rounded square, like a menu-bar app at rest.
        let corner = side * 0.22
        let background = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)
        NSGradient(colors: [
            NSColor(calibratedRed: 0.16, green: 0.15, blue: 0.22, alpha: 1),
            NSColor(calibratedRed: 0.09, green: 0.08, blue: 0.13, alpha: 1),
        ])?.draw(in: background, angle: -90)

        // The draining ring, three-quarters full, in the app's amber.
        let inset = side * 0.22
        let ringRect = rect.insetBy(dx: inset, dy: inset)
        let centre = NSPoint(x: rect.midX, y: rect.midY)
        let radius = ringRect.width / 2
        let lineWidth = max(1, side * 0.085)

        let track = NSBezierPath()
        track.appendArc(withCenter: centre, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = lineWidth
        NSColor(calibratedWhite: 1, alpha: 0.16).setStroke()
        track.stroke()

        let arc = NSBezierPath()
        arc.appendArc(withCenter: centre, radius: radius, startAngle: 90, endAngle: 90 - 270, clockwise: true)
        arc.lineWidth = lineWidth
        arc.lineCapStyle = .round
        NSColor(calibratedRed: 1.0, green: 0.63, blue: 0.29, alpha: 1).setStroke()
        arc.stroke()

        // The pupil: this is EyesUp, after all.
        let pupil = NSBezierPath(ovalIn: NSRect(x: centre.x - side * 0.055, y: centre.y - side * 0.055,
                                                width: side * 0.11, height: side * 0.11))
        NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.5, alpha: 1).setFill()
        pupil.fill()
        return true
    }
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
    bitmap.size = NSSize(width: side, height: side)
    return bitmap.representation(using: .png, properties: [:])
}

let iconset = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/AppIcon.iconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in iconSizes {
    guard let data = drawIcon(size: size) else { continue }
    try data.write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    if size <= 512, let retina = drawIcon(size: size * 2) {
        try retina.write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
    }
}
print("wrote \(iconset.path)")
```

- [ ] **Step 2: Generate it and wire it into the bundle**

Add to the `Makefile` (recipe lines start with a tab, and add `icon` to `.PHONY`):
```make
icon:
	swift Scripts/make-icon.swift build/AppIcon.iconset
	iconutil -c icns build/AppIcon.iconset -o Sources/EyesUpApp/Resources/AppIcon.icns
	@echo "Wrote Sources/EyesUpApp/Resources/AppIcon.icns"
```

In `Scripts/bundle.sh`, after the Info.plist copy:
```bash
cp Sources/EyesUpApp/Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
```

In `Sources/EyesUpApp/Resources/Info.plist`, add before the closing `</dict>`:
```xml
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
```

Run: `make icon && make app && open build/EyesUpGuardian.app`
Expected: `AppIcon.icns` is written; the app shows the ring icon in Finder, in the About window and in Notification Center banners. (The menu bar keeps its own template glyph.)

- [ ] **Step 3: Add an About window**

`Sources/EyesUpApp/About/AboutWindow.swift`:
```swift
import AppKit
import EyesUpCore
import SwiftUI

/// A small About panel: what this is, which version, and where to check what it's doing.
struct AboutView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
            Text("EyesUpGuardian").font(.title2.bold())
            Text("Version \(EyesUpCore.version)").font(.callout).foregroundStyle(.secondary)
            Text("Keeps your Mac awake, and shows you what it's doing.")
                .font(.callout)
                .multilineTextAlignment(.center)
            Text("It runs no commands, uses no network, and needs no admin rights.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("Check what it's holding:  pmset -g assertions | grep EyesUpGuardian")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
        }
        .padding(24)
        .frame(width: 340)
    }
}

@MainActor
final class AboutWindowController {
    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "About EyesUpGuardian"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: AboutView())
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        self.window = window
    }
}
```

In `StatusItemController`, add `var onShowAbout: (() -> Void)?`, a menu item above Quit:
```swift
        menu.addItem(menuItem("About EyesUpGuardian", #selector(showAbout)))
```
```swift
    @objc private func showAbout() { onShowAbout?() }
```
and in the app delegate, `let about = AboutWindowController()` with `statusItem.onShowAbout = { about.show() }`.

- [ ] **Step 4: Run the tests and look at it**

Run: `make test && make app && open build/EyesUpGuardian.app`
Expected: tests pass; right-click → **About EyesUpGuardian** shows the panel with the icon and version.

- [ ] **Step 5: Commit**

```bash
git add Scripts Sources Makefile
git commit -m "feat(app): add a generated app icon and an About window" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 13: Ready to publish

**Files:**
- Create: `LICENSE`, `CONTRIBUTING.md`, `.github/workflows/ci.yml`, `Scripts/release.sh`
- Modify: `Makefile` (a `perf-stats` target), `README.md`, `docs/manual-test-checklist.md`, `docs/superpowers/specs/2026-09-19-eyesupguardian-design.md`

- [ ] **Step 1: Add the license and contributing guide**

`LICENSE` — the MIT license, `Copyright (c) 2026 EyesUpGuardian contributors`.

`CONTRIBUTING.md`:
```markdown
# Contributing

Thanks for taking a look.

## Building

Requires macOS 26 and the Xcode Command Line Tools (`xcode-select --install`). Full Xcode is not needed.

```bash
make app     # build build/EyesUpGuardian.app
make test    # unit tests
make perf    # idle CPU and memory check
```

## The rules this project keeps

These are enforced by `Tests/EyesUpCoreTests/SecurityGuardTests.swift`, which fails the build:

- **No running commands, no network, no privilege escalation, no loading code at runtime.**
- **No third-party dependencies.** `Package.swift` declares none, and no binary targets or plugins.
- Anything that has to break a rule is marked `// security-allow: <why>` on the line itself. There is currently one.
- `EyesUpCore` contains the logic and no UI; `EyesUpApp` draws and forwards intents. Core must not import SwiftUI or AppKit.
- **Don't use SwiftUI `@State`.** With the Command Line Tools alone it needs a macro plugin that ships only with Xcode. Use an `@Observable` class and `@Bindable`.
- Tests first. Every behaviour change arrives with a test that failed before the change.
- Anything read from disk, from another process, or from a link is untrusted: range-check it, and put text through `SafeText.display`.

## Performance

The app must stay at **under 0.1% CPU and 30 MB when idle in its default configuration** — `make perf` checks it. Visible surfaces (dashboard, HUD, stats in the menu bar) are allowed up to 1.5%; `make perf-stats` measures that configuration.
```

- [ ] **Step 2: Add continuous integration**

`.github/workflows/ci.yml`:
```yaml
name: CI

on:
  push:
    branches: ["**"]
  pull_request:

jobs:
  test:
    # The app targets macOS 26, so it needs a runner with that SDK.
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4
      - name: Show toolchain
        run: swift --version && sw_vers
      - name: Unit tests
        run: make test
      - name: Build the app
        run: make app
      - name: Check the bundle is signed with the hardened runtime
        run: codesign -dv --verbose=2 build/EyesUpGuardian.app 2>&1 | grep -q 'flags=.*runtime'
```
Integration tests are left out on purpose: they take real power assertions and read hardware sensors, which a CI runner may not have.

- [ ] **Step 3: Add the release script**

`Scripts/release.sh` (then `chmod +x`):
```bash
#!/bin/bash
# Builds a distributable EyesUpGuardian.dmg.
#
# With no signing identity it produces an ad-hoc signed build: anyone downloading it has to
# right-click → Open once. Set DEVELOPER_ID (and NOTARY_PROFILE) to sign and notarize instead —
# no other change is needed.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(plutil -extract CFBundleShortVersionString raw Sources/EyesUpApp/Resources/Info.plist)"
APP="build/EyesUpGuardian.app"
DMG="build/EyesUpGuardian-$VERSION.dmg"

make app

if [ -n "${DEVELOPER_ID:-}" ]; then
    echo "Signing with: $DEVELOPER_ID"
    codesign --force --deep --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP"
    codesign --verify --strict --verbose=2 "$APP"
else
    echo "No DEVELOPER_ID set — shipping the ad-hoc signature."
fi

rm -f "$DMG"
STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "EyesUpGuardian" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"

if [ -n "${NOTARY_PROFILE:-}" ]; then
    echo "Notarizing…"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
fi

echo "Built $DMG"
shasum -a 256 "$DMG"
```

Add to the `Makefile` (and `.PHONY`):
```make
release:
	Scripts/release.sh

perf-stats:
	@echo "Measuring with the stats readout and HUD on (visible-surface budget, 1.5%)"
	SETTLE_SECONDS=20 SAMPLE_SECONDS=40 EYESUP_PERF_LIMIT=1.5 Scripts/perf.sh
```
and in `Scripts/perf.sh`, let the limit be overridden:
```bash
MAX_CPU_PERCENT="${EYESUP_PERF_LIMIT:-0.1}"
```

- [ ] **Step 4: Finish the README**

Add to `README.md`, after the features:
```markdown
## History and energy

The **History** tab shows how long your Mac was kept awake each day, what kept it awake, how many sessions there were, and the energy drawn. Set an electricity rate in Settings and it shows what that cost; leave it empty and it shows kilowatt-hours only, never a made-up number. The sleep/wake log records when your Mac actually slept.

## Shortcuts

- **⌃⌥⌘E** toggles keeping awake from anywhere. It needs no accessibility permission, because it uses a system hot key rather than watching your keyboard.
- **⌘1–⌘5** switch dashboard tabs.

## Install

```bash
git clone <your fork or this repo>
cd EyesUpGuardian
make install          # builds and copies to /Applications
open /Applications/EyesUpGuardian.app
```

The build is ad-hoc signed, so the first launch of a *downloaded* copy needs a right-click → Open. A copy you built yourself opens normally. To open it at login, turn on **Open EyesUpGuardian at login** in Settings.

## Verifying the claims yourself

See [SECURITY.md](SECURITY.md) — it lists every system interface the app touches and the commands to check that it holds no network connections, links no third-party code, and keeps nothing outside its own folder.
```

- [ ] **Step 5: Finish the checklist and the spec**

Append to `docs/manual-test-checklist.md`:
```markdown

## History, settings and shortcuts (Plan 4)
- [ ] A finished session appears in History with the right duration and reasons.
- [ ] Quitting while awake still records the session.
- [ ] The per-day chart matches what you did; switching 7/30 days changes it.
- [ ] With an electricity rate set, History shows money; with it empty, kWh only.
- [ ] Sleep and wake are logged when the Mac actually sleeps.
- [ ] Clear history empties the tab and the file.
- [ ] Preset toggles in Settings change the popover's buttons immediately.
- [ ] Export settings writes a file; Import restores it; importing rubbish is refused and changes nothing.
- [ ] Open at login: the toggle matches System Settings → Login Items, both ways.
- [ ] ⌃⌥⌘E toggles keep-awake from another app; turning the shortcut off stops it.
- [ ] ⌘1–⌘5 switch dashboard tabs.
- [ ] HUD snaps to a corner when dragged, fades when the pointer leaves, and passes clicks through when that's on.
- [ ] Right-click menu says "Unpin HUD" while the HUD is pinned.
- [ ] Menu-bar readout offers CPU, memory, power, temperature and network, and each shows what it promises.
- [ ] About shows the icon and version; the app icon appears in Finder.
- [ ] `make perf` passes (default configuration); `make perf-stats` stays under 1.5%.
```

In the spec, mark the deferred items done — in §7.4 replace the HUD paragraph's "optional click-through" line with a note that all four behaviours ship, and in §7.1 confirm the readout options are CPU, memory, power, temperature and network.

- [ ] **Step 6: Final verification**

Run: `make test && make test-integration && make perf && make perf-stats`
Expected: every suite green; `perf` PASS at the 0.1% idle limit; `perf-stats` PASS at the 1.5% visible limit.
Run: `make release`
Expected: a `build/EyesUpGuardian-0.1.0.dmg` with its SHA-256 printed, built without a Developer ID (ad-hoc) and without errors.
Then work through the whole of `docs/manual-test-checklist.md` — every section, not just Plan 4's.

- [ ] **Step 7: Commit**

```bash
git add LICENSE CONTRIBUTING.md .github Scripts Makefile README.md docs
git commit -m "chore: add license, CI, release script and the publishing docs" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```
