# EyesUpGuardian Plan 1: Awake Engine, Menu Bar and Popover

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a usable, safe keep-awake menu-bar app. It has:
- the full awake engine: timers, indefinite, until-a-time and until-a-PID-exits, with every `caffeinate` sleep type;
- a draining-ring menu-bar item;
- an Ambient-style popover;
- heads-up notifications;
- crash-safe restore.

**Architecture:**
- The Swift package has two targets. `EyesUpCore` holds all logic with no UI imports, and every macOS dependency sits behind a protocol so tests can inject fakes. `EyesUpApp` is a thin AppKit/SwiftUI layer: an `NSStatusItem` plus an `NSPopover` hosting SwiftUI.
- `AwakeController` owns the list of holds (the spec's "hold registry"). It drives `AwakeEngine`, which diffs the holds into IOKit power assertions. It also drives `DeadlineMonitor` (timers and heads-up) and `KqueueExitWatcher` (PID exit).

**Tech Stack:**
- Swift 6.2+ (strict concurrency), SwiftUI + AppKit on macOS 26.
- IOKit power management, libproc, Dispatch.
- Swift Testing.
- Swift Package Manager + Makefile. No Xcode, no third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-09-19-eyesupguardian-design.md`

### Where this plan fits (roadmap)

The spec is one app, but too large for one reviewable plan. It is split into four plans, and each ends with working software:

| Plan | Scope | Spec sections |
|---|---|---|
| **1 (this one)** | Core engine, persistence, menu-bar item, popover, heads-up notifications, security guard tests, perf check | §2, §3, §4.1–4.4, §7.1, §7.2 (without stat tiles), §7.5 (heads-up), §8 (holds file), §9, §10, §11 (partial) |
| 2 | Triggers, automation URL scheme, safety guards | §4.5, §5 |
| 3 | Private-probe feasibility spike (first task), metrics sampler and probes, dashboard window, floating HUD, popover stat tiles, menu-bar stat readout | §6, §7.1 readout stats, §7.2 tiles, §7.3 tabs 1 and 3, §7.4 |
| 4 | History and energy, Settings tab, launch at login, global hotkey, app icon, README, SECURITY.md, CI, release script | §6.3, §7.3 tabs 4–5, §8, §11 |

## Global Constraints

- Minimum OS: `platforms: [.macOS(.v26)]`, `// swift-tools-version: 6.2`, Swift 6 language mode (strict concurrency).
- **Zero third-party dependencies:** `Package.swift` must never contain `.package(`.
- **Never execute commands in app code:** no `Process`, `NSTask`, `posix_spawn`, `popen`, `system(`, `exec*`, `NSAppleScript`/`OSAScript`. Tests may spawn processes; `Sources/` may not.
- **No network in app code:** no `URLSession`, `Network.framework`, or `socket(`.
- **No privilege escalation:** no `sudo`, `AuthorizationExecuteWithPrivileges`, `AuthorizationCreate`, or `SMJobBless`.
- `EyesUpCore` must not import SwiftUI or AppKit. `Foundation`, `IOKit`, `Darwin`, `Dispatch` and `Observation` are allowed.
- Bundle ID `dev.eyesupguardian.EyesUpGuardian`; executable and app name `EyesUpGuardian`; `LSUIElement = YES`.
- Assertion names start with `EyesUpGuardian` and are at most 128 characters.
- Storage: `~/Library/Application Support/EyesUpGuardian/`, JSON with `schemaVersion`, atomic writes.
- **Idle targets (spec §3):**
  - CPU < 0.1% averaged over 60 s.
  - Memory footprint ≤ 30 MB. This is `phys_footprint`, the value Activity Monitor's Memory column shows.
- **No per-second work while nothing is visible.** The menu bar updates once a minute, and only while a deadline exists.
- End every commit message with the line `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
- **Toolchain note:** if `swift test` ever reports `plugin for module 'TestingMacros' not found`, run it again. If the error persists, run `rm -rf .build`. It's a known incremental-build flake with command-line-tools-only installs.

## Review Focus

1. **A PID that exited, or was recycled, between being typed and being watched.** The hold must end immediately, not keep the Mac awake forever. Tests: Task 6 `watcherFiresForAlreadyExitedProcess` and `watcherTreatsRecycledPIDAsExited`; Task 8 `watchProcessRejectsMissingProcess`.
2. **Garbage typed into the popover's duration or PID fields:** letters, negatives, zero, huge numbers, spaces, non-ASCII digits like `٣`. The user sees a clear error and no hold is created. Tests: Task 2 `rejectsInvalidDurations`; Task 8 `parsePIDRejectsGarbage`.
3. **The Mac slept, or the clock jumped, past a deadline.** On wake the expired hold ends at once and never lingers. Tests: Task 5 `pastDeadlineExpiresImmediately`. Task 10 wires wake and clock-change notifications to `refresh()`.
4. **`holds.json` is corrupt, truncated, oversized or from a future schema.** The app launches clean, the file is moved aside, and the user is told. Tests: Task 7 `corruptFileIsMovedAside`, `truncatedFile…`, `oversizedFile…`, `futureSchema…`; Task 8 `restoreReportsCorruptStore`.
5. **Overlapping holds.** Stopping one hold must not drop an assertion another hold still needs. Stopping all must release everything. A very long reasons list must not break the assertion name. Tests: Task 3 `removingOneOfTwoHoldsKeepsAssertion` and `longNamesAreTruncated`; Task 8 `stoppingOneOverlappingHoldKeepsMacAwake`.

---

## File map

```
EyesUpGuardian/
├── Package.swift                                   Task 1
├── Makefile                                        Task 1 (perf target in Task 13)
├── Scripts/bundle.sh                               Task 1
├── Scripts/perf.sh                                 Task 13
├── Sources/EyesUpCore/
│   ├── EyesUpCore.swift                            Task 1: version constant
│   ├── Holds/SleepPolicy.swift                     Task 2: SleepPolicy, AssertionKind
│   ├── Holds/Hold.swift                            Task 2: Hold, HoldSource, HoldEnd, ProcessIdentity
│   ├── Holds/DurationParser.swift                  Task 2
│   ├── Formatting/TimeFormatting.swift             Task 2
│   ├── Engine/PowerAssertionProviding.swift        Task 3
│   ├── Engine/AwakeEngine.swift                    Task 3
│   ├── Engine/IOKitPowerAssertions.swift           Task 4: real provider + SystemAssertions
│   ├── Engine/Scheduling.swift                     Task 5: WallClock, TimerScheduling, DispatchTimerScheduler
│   ├── Engine/DeadlineMonitor.swift                Task 5
│   ├── Processes/ProcessInspecting.swift           Task 6: LibprocInspector
│   ├── Processes/ProcessExitWatcher.swift          Task 6: KqueueExitWatcher
│   ├── Store/JSONFileStore.swift                   Task 7
│   ├── Store/HoldRestorer.swift                    Task 7
│   └── AwakeController.swift                       Task 8
├── Sources/EyesUpApp/
│   ├── Resources/Info.plist                        Task 1
│   ├── EyesUpGuardianApp.swift                     Task 1 (replaced in Task 10)
│   ├── AppEnvironment.swift                        Task 10
│   ├── MenuBar/RingIcon.swift                      Task 10
│   ├── MenuBar/StatusItemController.swift          Task 10 (popover hookup in Task 11)
│   ├── Popover/AmbientBackground.swift             Task 11
│   ├── Popover/PopoverView.swift                   Task 11
│   └── Notifications/HeadsUpNotifier.swift         Task 12
├── Tests/EyesUpCoreTests/
│   ├── Support/Fakes.swift                         grows in Tasks 2, 3, 5, 6
│   ├── Support/Traits.swift                        Task 4
│   ├── SmokeTests.swift                            Task 1
│   ├── ValueTypesTests.swift                       Task 2
│   ├── DurationParserTests.swift                   Task 2
│   ├── TimeFormattingTests.swift                   Task 2
│   ├── AwakeEngineTests.swift                      Task 3
│   ├── IOKitIntegrationTests.swift                 Task 4
│   ├── DeadlineMonitorTests.swift                  Task 5
│   ├── ProcessTests.swift                          Task 6
│   ├── StoreTests.swift                            Task 7
│   ├── AwakeControllerTests.swift                  Task 8
│   └── SecurityGuardTests.swift                    Task 9
└── docs/manual-test-checklist.md                   Task 13
```

---

### Task 1: Package scaffold, bundling and a launchable placeholder app

**Files:**
- Create: `Package.swift`, `Makefile`, `Scripts/bundle.sh`, `Sources/EyesUpCore/EyesUpCore.swift`, `Sources/EyesUpApp/Resources/Info.plist`, `Sources/EyesUpApp/EyesUpGuardianApp.swift`, `Tests/EyesUpCoreTests/SmokeTests.swift`

**Interfaces:**
- Produces:
  - `EyesUpCore.version: String`;
  - the `make app` / `make test` / `make test-integration` / `make install` / `make run` / `make clean` targets;
  - `build/EyesUpGuardian.app`.

- [ ] **Step 1: Write the failing smoke test**

`Tests/EyesUpCoreTests/SmokeTests.swift`:
```swift
import Testing
@testable import EyesUpCore

@Test func versionIsSemantic() {
    #expect(EyesUpCore.version.split(separator: ".").count == 3)
}
```

- [ ] **Step 2: Create `Package.swift`**

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EyesUpGuardian",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "EyesUpGuardian", targets: ["EyesUpApp"]),
    ],
    targets: [
        .target(
            name: "EyesUpCore",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .executableTarget(
            name: "EyesUpApp",
            dependencies: ["EyesUpCore"],
            exclude: ["Resources"]
        ),
        .testTarget(
            name: "EyesUpCoreTests",
            dependencies: ["EyesUpCore"]
        ),
    ]
)
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `swift test`
Expected: build FAILS. `EyesUpCore` has no sources yet, and the app target has none either.

- [ ] **Step 4: Add the minimal core and a placeholder app**

`Sources/EyesUpCore/EyesUpCore.swift`:
```swift
/// Namespace for package-wide constants.
public enum EyesUpCore {
    public static let version = "0.1.0"
}
```

`Sources/EyesUpApp/EyesUpGuardianApp.swift` (a placeholder replaced in Task 10; it proves bundling and the menu bar work):
```swift
import AppKit
import SwiftUI

@main
struct EyesUpGuardianApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene { Settings { EmptyView() } }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "eye", accessibilityDescription: "EyesUpGuardian")
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit EyesUpGuardian", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }
}
```

`Sources/EyesUpApp/Resources/Info.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>EyesUpGuardian</string>
    <key>CFBundleIdentifier</key><string>dev.eyesupguardian.EyesUpGuardian</string>
    <key>CFBundleName</key><string>EyesUpGuardian</string>
    <key>CFBundleDisplayName</key><string>EyesUpGuardian</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict>
</plist>
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `swift test`
Expected: `✔ Test versionIsSemantic() passed`.

- [ ] **Step 6: Add the bundle script and Makefile**

`Scripts/bundle.sh` (then `chmod +x Scripts/bundle.sh`):
```bash
#!/bin/bash
# Assembles build/EyesUpGuardian.app from the SwiftPM binary and ad-hoc signs it with Hardened Runtime.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/EyesUpGuardian.app"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/EyesUpGuardian" "$APP/Contents/MacOS/EyesUpGuardian"
cp Sources/EyesUpApp/Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --options runtime --sign - "$APP"
codesign --verify --strict "$APP"
echo "Built $APP"
```

`Makefile`. Recipe lines **must start with a tab character**:
```make
.PHONY: app test test-integration install run clean

app:
	swift build -c release --product EyesUpGuardian
	Scripts/bundle.sh release

test:
	swift test

test-integration:
	EYESUP_INTEGRATION=1 swift test

install: app
	rm -rf /Applications/EyesUpGuardian.app
	cp -R build/EyesUpGuardian.app /Applications/

run: app
	open build/EyesUpGuardian.app

clean:
	swift package clean
	rm -rf build
```

- [ ] **Step 7: Build and verify the bundle**

Run: `make app && codesign -dv build/EyesUpGuardian.app 2>&1 | grep -E "Identifier|flags"`
Expected:
- `Built build/EyesUpGuardian.app`;
- `Identifier=dev.eyesupguardian.EyesUpGuardian`;
- a `flags=` line containing `runtime`.

Run: `open build/EyesUpGuardian.app`
Expected: an eye icon appears in the menu bar and no Dock icon. Clicking it shows "Quit EyesUpGuardian", and choosing that quits the app.

- [ ] **Step 8: Commit**

```bash
git add Package.swift Makefile Scripts/bundle.sh Sources Tests
git commit -m "chore: scaffold Swift package, app bundle script and Makefile" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: Core value types: policies, holds, duration parsing, time formatting

**Files:**
- Create: `Sources/EyesUpCore/Holds/SleepPolicy.swift`, `Sources/EyesUpCore/Holds/Hold.swift`, `Sources/EyesUpCore/Holds/DurationParser.swift`, `Sources/EyesUpCore/Formatting/TimeFormatting.swift`
- Create: `Tests/EyesUpCoreTests/Support/Fakes.swift`, `Tests/EyesUpCoreTests/ValueTypesTests.swift`, `Tests/EyesUpCoreTests/DurationParserTests.swift`, `Tests/EyesUpCoreTests/TimeFormattingTests.swift`

**Interfaces:**
- Produces:
  - `struct SleepPolicy: OptionSet` with `.system`, `.display`, `.disk`, `.systemOnAC`.
  - `enum AssertionKind` with `.preventDisplaySleep`, `.preventIdleSystemSleep`, `.preventSystemSleep`, `.preventDiskIdle`; `var ioKitType: String`; `static func kinds(for: SleepPolicy) -> Set<AssertionKind>`.
  - `struct ProcessIdentity { pid: Int32; startTime: UInt64 }`.
  - `enum HoldSource { case manual, trigger(UUID), automation }` with `var isTrigger: Bool`.
  - `enum HoldEnd { case indefinite, deadline(Date), processExit(ProcessIdentity), triggerControlled }`.
  - `struct Hold` with `id`, `source`, `label`, `policy`, `end`, `grace: TimeInterval?`, `createdAt`; `var effectiveDeadline: Date?`; `var isManualSession: Bool`; `static func awakeUntil(_ holds: [Hold]) -> Date?`.
  - `enum ParsedDuration { case finite(TimeInterval), infinite }`; `DurationParser.parse(_:) -> ParsedDuration?`.
  - `TimeFormatting.duration(_:)`, `.menuBar(remaining:)`, `.countdown(_:)`, `.remainingFraction(now:start:end:)`.
  - Test helper `makeHold(...)`.

- [ ] **Step 1: Write the failing tests**

`Tests/EyesUpCoreTests/Support/Fakes.swift`:
```swift
import Foundation
@testable import EyesUpCore

let referenceDate = Date(timeIntervalSince1970: 1_000_000)

func makeHold(
    label: String = "Test hold",
    policy: SleepPolicy = .system,
    end: HoldEnd = .indefinite,
    grace: TimeInterval? = nil,
    source: HoldSource = .manual,
    createdAt: Date = referenceDate
) -> Hold {
    Hold(source: source, label: label, policy: policy, end: end, grace: grace, createdAt: createdAt)
}
```

`Tests/EyesUpCoreTests/ValueTypesTests.swift`:
```swift
import Foundation
import Testing
@testable import EyesUpCore

@Suite struct ValueTypesTests {
    @Test func policyMapsToAssertionKinds() {
        #expect(AssertionKind.kinds(for: .system) == [.preventIdleSystemSleep])
        #expect(AssertionKind.kinds(for: [.system, .display]) == [.preventIdleSystemSleep, .preventDisplaySleep])
        #expect(AssertionKind.kinds(for: [.disk, .systemOnAC]) == [.preventDiskIdle, .preventSystemSleep])
        #expect(AssertionKind.kinds(for: []).isEmpty)
    }

    @Test func assertionKindsUseIOKitNames() {
        #expect(AssertionKind.preventDisplaySleep.ioKitType == "PreventUserIdleDisplaySleep")
        #expect(AssertionKind.preventIdleSystemSleep.ioKitType == "PreventUserIdleSystemSleep")
        #expect(AssertionKind.preventSystemSleep.ioKitType == "PreventSystemSleep")
        #expect(AssertionKind.preventDiskIdle.ioKitType == "PreventDiskIdle")
    }

    @Test func holdsRoundTripThroughJSON() throws {
        let holds = [
            makeHold(end: .indefinite),
            makeHold(end: .deadline(referenceDate.addingTimeInterval(60)), grace: 30),
            makeHold(end: .processExit(ProcessIdentity(pid: 42, startTime: 123)), source: .automation),
            makeHold(end: .triggerControlled, source: .trigger(UUID())),
        ]
        let data = try JSONEncoder().encode(holds)
        #expect(try JSONDecoder().decode([Hold].self, from: data) == holds)
    }

    @Test func effectiveDeadlineIncludesGrace() {
        let hold = makeHold(end: .deadline(referenceDate), grace: 300)
        #expect(hold.effectiveDeadline == referenceDate.addingTimeInterval(300))
        #expect(makeHold(end: .indefinite).effectiveDeadline == nil)
    }

    @Test func awakeUntilIsLatestDeadlineOnlyWhenAllHoldsHaveOne() {
        let a = makeHold(end: .deadline(referenceDate.addingTimeInterval(60)))
        let b = makeHold(end: .deadline(referenceDate.addingTimeInterval(600)))
        #expect(Hold.awakeUntil([a, b]) == referenceDate.addingTimeInterval(600))
        #expect(Hold.awakeUntil([a, makeHold(end: .indefinite)]) == nil)
        #expect(Hold.awakeUntil([]) == nil)
    }

    @Test func manualSessionCoversTimersAndIndefiniteOnly() {
        #expect(makeHold(end: .indefinite).isManualSession)
        #expect(makeHold(end: .deadline(referenceDate)).isManualSession)
        #expect(!makeHold(end: .processExit(ProcessIdentity(pid: 1, startTime: 1))).isManualSession)
        #expect(!makeHold(end: .indefinite, source: .automation).isManualSession)
        #expect(!makeHold(end: .triggerControlled, source: .trigger(UUID())).isManualSession)
    }
}
```

`Tests/EyesUpCoreTests/DurationParserTests.swift`:
```swift
import Testing
@testable import EyesUpCore

@Suite struct DurationParserTests {
    @Test(arguments: [
        ("90m", 5400.0), ("2h", 7200.0), ("1h30m", 5400.0), (" 2H ", 7200.0), ("999h", 3_596_400.0), ("1m", 60.0),
    ])
    func parsesValidDurations(text: String, seconds: Double) {
        #expect(DurationParser.parse(text) == .finite(seconds))
    }

    @Test func parsesInfinity() {
        #expect(DurationParser.parse("inf") == .infinite)
        #expect(DurationParser.parse(" INF ") == .infinite)
    }

    @Test(arguments: ["", " ", "0m", "0h0m", "h", "m", "1h1h", "-5m", "1000h", "12345m", "1.5h", "2h 30m", "٣h", "2d", "30", "1h30m5s"])
    func rejectsInvalidDurations(text: String) {
        #expect(DurationParser.parse(text) == nil)
    }
}
```

`Tests/EyesUpCoreTests/TimeFormattingTests.swift`:
```swift
import Foundation
import Testing
@testable import EyesUpCore

@Suite struct TimeFormattingTests {
    @Test func durationLabels() {
        #expect(TimeFormatting.duration(7200) == "2h")
        #expect(TimeFormatting.duration(5400) == "1h 30m")
        #expect(TimeFormatting.duration(900) == "15m")
        #expect(TimeFormatting.duration(20) == "<1m")
    }

    @Test func menuBarReadout() {
        #expect(TimeFormatting.menuBar(remaining: 6120) == "1:42")
        #expect(TimeFormatting.menuBar(remaining: 3600) == "1:00")
        #expect(TimeFormatting.menuBar(remaining: 2519) == "42m")
        #expect(TimeFormatting.menuBar(remaining: 30) == "1m")
        #expect(TimeFormatting.menuBar(remaining: -5) == "0m")
    }

    @Test func countdown() {
        #expect(TimeFormatting.countdown(6130) == "1:42:10")
        #expect(TimeFormatting.countdown(2530) == "42:10")
        #expect(TimeFormatting.countdown(-1) == "0:00")
    }

    @Test func remainingFractionIsClamped() {
        let start = referenceDate
        let end = start.addingTimeInterval(100)
        #expect(TimeFormatting.remainingFraction(now: start.addingTimeInterval(25), start: start, end: end) == 0.75)
        #expect(TimeFormatting.remainingFraction(now: end.addingTimeInterval(10), start: start, end: end) == 0)
        #expect(TimeFormatting.remainingFraction(now: start.addingTimeInterval(-10), start: start, end: end) == 1)
        #expect(TimeFormatting.remainingFraction(now: start, start: start, end: start) == 0)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test`
Expected: FAIL to compile with `cannot find 'SleepPolicy' in scope` (and similar).

- [ ] **Step 3: Implement the value types**

`Sources/EyesUpCore/Holds/SleepPolicy.swift`:
```swift
/// Which kinds of sleep a hold prevents. Mirrors caffeinate's -i, -d, -m and -s flags.
public struct SleepPolicy: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// caffeinate -i: keep the Mac awake; the display may sleep.
    public static let system = SleepPolicy(rawValue: 1 << 0)
    /// caffeinate -d: keep the display on.
    public static let display = SleepPolicy(rawValue: 1 << 1)
    /// caffeinate -m: keep disks from idling.
    public static let disk = SleepPolicy(rawValue: 1 << 2)
    /// caffeinate -s: prevent all system sleep (macOS honors this only on AC power).
    public static let systemOnAC = SleepPolicy(rawValue: 1 << 3)
}

/// One IOKit power assertion type.
public enum AssertionKind: String, CaseIterable, Hashable, Sendable {
    case preventDisplaySleep
    case preventIdleSystemSleep
    case preventSystemSleep
    case preventDiskIdle

    /// The assertion type string IOKit expects.
    public var ioKitType: String {
        switch self {
        case .preventDisplaySleep: "PreventUserIdleDisplaySleep"
        case .preventIdleSystemSleep: "PreventUserIdleSystemSleep"
        case .preventSystemSleep: "PreventSystemSleep"
        case .preventDiskIdle: "PreventDiskIdle"
        }
    }

    public static func kinds(for policy: SleepPolicy) -> Set<AssertionKind> {
        var kinds: Set<AssertionKind> = []
        if policy.contains(.system) { kinds.insert(.preventIdleSystemSleep) }
        if policy.contains(.display) { kinds.insert(.preventDisplaySleep) }
        if policy.contains(.disk) { kinds.insert(.preventDiskIdle) }
        if policy.contains(.systemOnAC) { kinds.insert(.preventSystemSleep) }
        return kinds
    }
}
```

`Sources/EyesUpCore/Holds/Hold.swift`:
```swift
import Foundation

/// A process pinned by PID *and* start time, so a recycled PID is never mistaken for the original.
public struct ProcessIdentity: Codable, Hashable, Sendable {
    public let pid: Int32
    /// Start time in microseconds since 1970.
    public let startTime: UInt64

    public init(pid: Int32, startTime: UInt64) {
        self.pid = pid
        self.startTime = startTime
    }
}

public enum HoldSource: Codable, Hashable, Sendable {
    case manual
    case trigger(UUID)
    case automation

    public var isTrigger: Bool {
        if case .trigger = self { return true }
        return false
    }
}

public enum HoldEnd: Codable, Hashable, Sendable {
    case indefinite
    case deadline(Date)
    case processExit(ProcessIdentity)
    case triggerControlled
}

/// One reason to keep the Mac awake.
public struct Hold: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var source: HoldSource
    public var label: String
    public var policy: SleepPolicy
    public var end: HoldEnd
    /// Extra time to stay awake after the end condition is met.
    public var grace: TimeInterval?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        source: HoldSource = .manual,
        label: String,
        policy: SleepPolicy,
        end: HoldEnd,
        grace: TimeInterval? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.source = source
        self.label = label
        self.policy = policy
        self.end = end
        self.grace = grace
        self.createdAt = createdAt
    }

    /// The moment this hold expires, including grace; nil if it has no deadline.
    public var effectiveDeadline: Date? {
        guard case .deadline(let date) = end else { return nil }
        return date.addingTimeInterval(grace ?? 0)
    }

    /// A manual timer or indefinite session. Starting a new one replaces the old one.
    public var isManualSession: Bool {
        guard source == .manual else { return false }
        switch end {
        case .indefinite, .deadline: return true
        case .processExit, .triggerControlled: return false
        }
    }

    /// When the Mac may sleep again, or nil if there are no holds or any hold has no deadline.
    public static func awakeUntil(_ holds: [Hold]) -> Date? {
        guard !holds.isEmpty else { return nil }
        var latest = Date.distantPast
        for hold in holds {
            guard let deadline = hold.effectiveDeadline else { return nil }
            latest = max(latest, deadline)
        }
        return latest
    }
}
```

`Sources/EyesUpCore/Holds/DurationParser.swift`:
```swift
import Foundation

public enum ParsedDuration: Equatable, Sendable {
    case finite(TimeInterval)
    case infinite
}

/// Parses user-typed durations such as "45m", "2h", "1h30m" or "inf". Everything else is rejected.
public enum DurationParser {
    public static func parse(_ text: String) -> ParsedDuration? {
        let input = text.trimmingCharacters(in: .whitespaces).lowercased()
        if input == "inf" { return .infinite }
        guard !input.isEmpty, input.count <= 9 else { return nil }

        let pattern = /(?:(\d{1,3})h)?(?:(\d{1,4})m)?/.asciiOnlyDigits()
        guard let match = input.wholeMatch(of: pattern), match.1 != nil || match.2 != nil else { return nil }

        let hours = match.1.flatMap { Int($0) } ?? 0
        let minutes = match.2.flatMap { Int($0) } ?? 0
        let total = hours * 3600 + minutes * 60
        guard total > 0 else { return nil }
        return .finite(TimeInterval(total))
    }
}
```

`Sources/EyesUpCore/Formatting/TimeFormatting.swift`:
```swift
import Foundation

public enum TimeFormatting {
    /// Hold labels: "2h", "1h 30m", "15m", "<1m".
    public static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        guard minutes >= 1 else { return "<1m" }
        let hours = minutes / 60
        let rest = minutes % 60
        if hours > 0 && rest > 0 { return "\(hours)h \(rest)m" }
        if hours > 0 { return "\(hours)h" }
        return "\(rest)m"
    }

    /// Menu-bar readout: "1:42" from one hour up, "42m" below, rounded up to the next minute.
    public static func menuBar(remaining seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "0m" }
        let minutes = Int((seconds / 60).rounded(.up))
        if minutes >= 60 { return String(format: "%d:%02d", minutes / 60, minutes % 60) }
        return "\(minutes)m"
    }

    /// Live countdown: "1:42:10" or "42:10".
    public static func countdown(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// Share of the session still remaining, clamped to 0...1. Drives the draining ring.
    public static func remainingFraction(now: Date, start: Date, end: Date) -> Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        return min(1, max(0, end.timeIntervalSince(now) / total))
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test`
Expected: all tests in `ValueTypesTests`, `DurationParserTests` and `TimeFormattingTests` pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/EyesUpCore Tests/EyesUpCoreTests
git commit -m "feat(core): add sleep policies, holds, duration parsing and time formatting" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: Awake engine (holds → power assertions)

**Files:**
- Create: `Sources/EyesUpCore/Engine/PowerAssertionProviding.swift`, `Sources/EyesUpCore/Engine/AwakeEngine.swift`, `Tests/EyesUpCoreTests/AwakeEngineTests.swift`
- Modify: `Tests/EyesUpCoreTests/Support/Fakes.swift` (append `FakePowerAssertions`)

**Interfaces:**
- Consumes: `Hold`, `AssertionKind`.
- Produces:
  - `struct PowerAssertionError: Error { kind: AssertionKind; code: Int32 }`.
  - `@MainActor protocol PowerAssertionProviding` with `create(_:name:) throws -> UInt32`, `rename(_:to:)`, `release(_:)`, `declareUserActivity(name:)`.
  - `@MainActor final class AwakeEngine` with `init(provider:)`, `reconcile(holds:)`, `releaseAll()`, `active: [AssertionKind: UInt32]`, `lastError: PowerAssertionError?`, `static assertionName(for:) -> String`, `static maxNameLength = 128`.

- [ ] **Step 1: Write the fake and the failing tests**

Append to `Tests/EyesUpCoreTests/Support/Fakes.swift`:
```swift
@MainActor
final class FakePowerAssertions: PowerAssertionProviding {
    private(set) var live: [UInt32: (kind: AssertionKind, name: String)] = [:]
    private(set) var createCount = 0
    private(set) var userActivityCount = 0
    var failingKinds: Set<AssertionKind> = []
    private var nextID: UInt32 = 1

    var liveKinds: Set<AssertionKind> { Set(live.values.map(\.kind)) }
    var liveNames: Set<String> { Set(live.values.map(\.name)) }

    func create(_ kind: AssertionKind, name: String) throws -> UInt32 {
        if failingKinds.contains(kind) { throw PowerAssertionError(kind: kind, code: -536870201) }
        createCount += 1
        let id = nextID
        nextID += 1
        live[id] = (kind, name)
        return id
    }

    func rename(_ id: UInt32, to name: String) { live[id]?.name = name }
    func release(_ id: UInt32) { live[id] = nil }
    func declareUserActivity(name: String) { userActivityCount += 1 }
}
```

`Tests/EyesUpCoreTests/AwakeEngineTests.swift`:
```swift
import Testing
@testable import EyesUpCore

@Suite @MainActor struct AwakeEngineTests {
    let provider = FakePowerAssertions()

    @Test func singleHoldTakesOneNamedAssertion() {
        let engine = AwakeEngine(provider: provider)
        engine.reconcile(holds: [makeHold(label: "Timer 2h")])
        #expect(provider.liveKinds == [.preventIdleSystemSleep])
        #expect(provider.liveNames == ["EyesUpGuardian: Timer 2h"])
    }

    @Test func overlappingHoldsShareOneAssertionPerKind() {
        let engine = AwakeEngine(provider: provider)
        engine.reconcile(holds: [makeHold(label: "Timer 2h"), makeHold(label: "Claude running")])
        #expect(provider.live.count == 1)
        #expect(provider.liveNames == ["EyesUpGuardian: Timer 2h · Claude running"])
    }

    @Test func addingDisplayPolicyAddsOnlyTheDisplayAssertion() {
        let engine = AwakeEngine(provider: provider)
        let timer = makeHold(label: "Timer 2h")
        engine.reconcile(holds: [timer])
        engine.reconcile(holds: [timer, makeHold(label: "Movie", policy: [.system, .display])])
        #expect(provider.liveKinds == [.preventIdleSystemSleep, .preventDisplaySleep])
        #expect(provider.createCount == 2)
    }

    @Test func removingOneOfTwoHoldsKeepsAssertion() {
        let engine = AwakeEngine(provider: provider)
        let a = makeHold(label: "A")
        let b = makeHold(label: "B")
        engine.reconcile(holds: [a, b])
        engine.reconcile(holds: [b])
        #expect(provider.liveKinds == [.preventIdleSystemSleep])
        #expect(provider.createCount == 1)
        #expect(provider.liveNames == ["EyesUpGuardian: B"])
    }

    @Test func noHoldsReleasesEverything() {
        let engine = AwakeEngine(provider: provider)
        engine.reconcile(holds: [makeHold(policy: [.system, .display, .disk, .systemOnAC])])
        #expect(provider.live.count == 4)
        engine.releaseAll()
        #expect(provider.live.isEmpty)
        #expect(engine.active.isEmpty)
    }

    @Test func longNamesAreTruncated() {
        let holds = (0..<40).map { makeHold(label: "Very long reason number \($0)") }
        let name = AwakeEngine.assertionName(for: holds)
        #expect(name.count == AwakeEngine.maxNameLength)
        #expect(name.hasPrefix("EyesUpGuardian: "))
        #expect(name.hasSuffix("…"))
    }

    @Test func failureIsReportedAndRetriedOnNextReconcile() {
        let engine = AwakeEngine(provider: provider)
        provider.failingKinds = [.preventDisplaySleep]
        let hold = makeHold(policy: [.system, .display])
        engine.reconcile(holds: [hold])
        #expect(engine.lastError?.kind == .preventDisplaySleep)
        #expect(provider.liveKinds == [.preventIdleSystemSleep])

        provider.failingKinds = []
        engine.reconcile(holds: [hold])
        #expect(engine.lastError == nil)
        #expect(provider.liveKinds == [.preventIdleSystemSleep, .preventDisplaySleep])
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter AwakeEngineTests`
Expected: FAIL to compile with `cannot find type 'PowerAssertionProviding' in scope`.

- [ ] **Step 3: Implement the protocol and engine**

`Sources/EyesUpCore/Engine/PowerAssertionProviding.swift`:
```swift
public struct PowerAssertionError: Error, Equatable, Sendable {
    public let kind: AssertionKind
    /// The IOReturn code macOS returned.
    public let code: Int32

    public init(kind: AssertionKind, code: Int32) {
        self.kind = kind
        self.code = code
    }
}

/// The only way the app touches macOS power management. Tests substitute a fake.
@MainActor
public protocol PowerAssertionProviding: AnyObject {
    func create(_ kind: AssertionKind, name: String) throws -> UInt32
    func rename(_ id: UInt32, to name: String)
    func release(_ id: UInt32)
    /// caffeinate -u: report user activity so the display wakes and idle timers reset.
    func declareUserActivity(name: String)
}
```

`Sources/EyesUpCore/Engine/AwakeEngine.swift`:
```swift
/// Turns the current set of holds into the minimum set of power assertions (at most one per kind).
@MainActor
public final class AwakeEngine {
    public static let maxNameLength = 128

    public private(set) var active: [AssertionKind: UInt32] = [:]
    public private(set) var lastError: PowerAssertionError?
    private var currentName = ""
    private let provider: any PowerAssertionProviding

    public init(provider: any PowerAssertionProviding) {
        self.provider = provider
    }

    public func reconcile(holds: [Hold]) {
        let desired = holds.reduce(into: Set<AssertionKind>()) { $0.formUnion(AssertionKind.kinds(for: $1.policy)) }
        let name = Self.assertionName(for: holds)
        lastError = nil

        for (kind, id) in active where !desired.contains(kind) {
            provider.release(id)
            active[kind] = nil
        }
        if name != currentName {
            for id in active.values { provider.rename(id, to: name) }
        }
        for kind in AssertionKind.allCases where desired.contains(kind) && active[kind] == nil {
            do {
                active[kind] = try provider.create(kind, name: name)
            } catch let error as PowerAssertionError {
                lastError = error
            } catch {
                lastError = PowerAssertionError(kind: kind, code: -1)
            }
        }
        currentName = active.isEmpty ? "" : name
    }

    public func releaseAll() {
        reconcile(holds: [])
    }

    /// "EyesUpGuardian: Timer 2h · Claude running", visible in `pmset -g assertions`.
    public static func assertionName(for holds: [Hold]) -> String {
        let prefix = "EyesUpGuardian"
        guard !holds.isEmpty else { return prefix }
        let full = prefix + ": " + holds.map(\.label).joined(separator: " · ")
        guard full.count > maxNameLength else { return full }
        return String(full.prefix(maxNameLength - 1)) + "…"
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter AwakeEngineTests`
Expected: 7 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/EyesUpCore/Engine Tests/EyesUpCoreTests
git commit -m "feat(core): add awake engine that reconciles holds into power assertions" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: Real IOKit power assertions + integration tests

**Files:**
- Create: `Sources/EyesUpCore/Engine/IOKitPowerAssertions.swift`, `Tests/EyesUpCoreTests/Support/Traits.swift`, `Tests/EyesUpCoreTests/IOKitIntegrationTests.swift`

**Interfaces:**
- Consumes: `PowerAssertionProviding`, `AwakeEngine`.
- Produces:
  - `@MainActor final class IOKitPowerAssertions: PowerAssertionProviding` (`init()`).
  - `struct SystemAssertion { pid: Int32; type: String; name: String }`.
  - `enum SystemAssertions` with `static func all() -> [SystemAssertion]` and `static func forProcess(_ pid: Int32) -> [SystemAssertion]`. Plan 3's "other apps keeping the Mac awake" also uses these.
  - Test trait `.integration`, enabled by `EYESUP_INTEGRATION=1`.

- [ ] **Step 1: Write the failing integration tests**

`Tests/EyesUpCoreTests/Support/Traits.swift`:
```swift
import Foundation
import Testing

extension Trait where Self == ConditionTrait {
    /// Tests that touch real macOS power management. Run with `make test-integration`.
    static var integration: Self {
        .enabled(if: ProcessInfo.processInfo.environment["EYESUP_INTEGRATION"] == "1", "set EYESUP_INTEGRATION=1")
    }
}
```

`Tests/EyesUpCoreTests/IOKitIntegrationTests.swift`:
```swift
import Foundation
import Testing
@testable import EyesUpCore

@Suite(.integration) @MainActor struct IOKitIntegrationTests {
    private func ownAssertionNames() -> [String] {
        SystemAssertions.forProcess(getpid()).map(\.name)
    }

    @Test func createRenameRelease() throws {
        let provider = IOKitPowerAssertions()
        let id = try provider.create(.preventIdleSystemSleep, name: "EyesUpGuardian-test-A")
        #expect(SystemAssertions.forProcess(getpid()).contains {
            $0.name == "EyesUpGuardian-test-A" && $0.type == "PreventUserIdleSystemSleep"
        })

        provider.rename(id, to: "EyesUpGuardian-test-B")
        #expect(ownAssertionNames().contains("EyesUpGuardian-test-B"))

        provider.release(id)
        #expect(!ownAssertionNames().contains("EyesUpGuardian-test-B"))
    }

    @Test func engineHoldsAndReleasesRealAssertions() {
        let engine = AwakeEngine(provider: IOKitPowerAssertions())
        engine.reconcile(holds: [makeHold(label: "integration", policy: [.system, .display])])
        let assertions = SystemAssertions.forProcess(getpid())
        #expect(Set(assertions.map(\.type)).isSuperset(of: ["PreventUserIdleSystemSleep", "PreventUserIdleDisplaySleep"]))
        #expect(assertions.allSatisfy { $0.name == "EyesUpGuardian: integration" })

        engine.releaseAll()
        #expect(SystemAssertions.forProcess(getpid()).isEmpty)
    }

    @Test func declaringUserActivityDoesNotThrowOrLeak() async throws {
        IOKitPowerAssertions().declareUserActivity(name: "EyesUpGuardian-test-nudge")
        try await Task.sleep(for: .seconds(6))
        #expect(!ownAssertionNames().contains("EyesUpGuardian-test-nudge"))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test-integration`
Expected: FAIL to compile with `cannot find 'IOKitPowerAssertions' in scope`.

- [ ] **Step 3: Implement the provider**

`Sources/EyesUpCore/Engine/IOKitPowerAssertions.swift`:
```swift
import Foundation
import IOKit.pwr_mgt

/// Real power assertions via IOKit: the same mechanism `caffeinate` uses, without launching it.
@MainActor
public final class IOKitPowerAssertions: PowerAssertionProviding {
    public init() {}

    public func create(_ kind: AssertionKind, name: String) throws -> UInt32 {
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kind.ioKitType as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            name as CFString,
            &id
        )
        guard result == kIOReturnSuccess else { throw PowerAssertionError(kind: kind, code: result) }
        return id
    }

    public func rename(_ id: UInt32, to name: String) {
        _ = IOPMAssertionSetProperty(id, "AssertName" as CFString, name as CFString)
    }

    public func release(_ id: UInt32) {
        _ = IOPMAssertionRelease(id)
    }

    public func declareUserActivity(name: String) {
        var id = IOPMAssertionID(0)
        guard IOPMAssertionDeclareUserActivity(name as CFString, kIOPMUserActiveLocal, &id) == kIOReturnSuccess else { return }
        // Match caffeinate -u, which holds the activity assertion for 5 seconds.
        let assertionID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { _ = IOPMAssertionRelease(assertionID) }
    }
}

/// A power assertion held by any process on the system.
public struct SystemAssertion: Hashable, Sendable {
    public let pid: Int32
    public let type: String
    public let name: String
}

public enum SystemAssertions {
    public static func all() -> [SystemAssertion] {
        var raw: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&raw) == kIOReturnSuccess,
              let byProcess = raw?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return [] }
        return byProcess.flatMap { pid, list in
            list.map {
                SystemAssertion(
                    pid: pid.int32Value,
                    type: $0["AssertType"] as? String ?? "",
                    name: $0["AssertName"] as? String ?? ""
                )
            }
        }
    }

    public static func forProcess(_ pid: Int32) -> [SystemAssertion] {
        all().filter { $0.pid == pid }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `make test-integration`
Expected: all tests pass, including the 3 in `IOKitIntegrationTests` (the nudge test takes about 6 s).
Run: `swift test`
Expected: the integration suite is skipped and the other tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/EyesUpCore/Engine/IOKitPowerAssertions.swift Tests/EyesUpCoreTests
git commit -m "feat(core): add IOKit power assertion provider and system assertion listing" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: Clock, timer scheduling and the deadline monitor

**Files:**
- Create: `Sources/EyesUpCore/Engine/Scheduling.swift`, `Sources/EyesUpCore/Engine/DeadlineMonitor.swift`, `Tests/EyesUpCoreTests/DeadlineMonitorTests.swift`
- Modify: `Tests/EyesUpCoreTests/Support/Fakes.swift` (append `FakeClock`, `FakeTask`, `FakeScheduler`)

**Interfaces:**
- Consumes: `Hold.effectiveDeadline`, `Hold.awakeUntil(_:)`.
- Produces:
  - `protocol WallClock: Sendable { var now: Date { get } }` and `struct SystemClock`.
  - `@MainActor protocol ScheduledTask: AnyObject { func cancel() }`.
  - `@MainActor protocol TimerScheduling: AnyObject { func schedule(at: Date, _ action: @escaping @MainActor @Sendable () -> Void) -> any ScheduledTask }`.
  - `DispatchTimerScheduler` and internal `DispatchSourceTask(_ source: any DispatchSourceProtocol)`.
  - `@MainActor final class DeadlineMonitor` with `init(clock:scheduler:headsUpLead:)`, `update(holds:)`, `onExpired: (([UUID]) -> Void)?`, `onHeadsUp: ((Date) -> Void)?`, `headsUpLead`.

- [ ] **Step 1: Write the fakes and the failing tests**

Append to `Tests/EyesUpCoreTests/Support/Fakes.swift`:
```swift
final class FakeClock: WallClock, @unchecked Sendable {
    var now: Date
    init(_ now: Date = referenceDate) { self.now = now }
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

@MainActor
final class FakeTask: ScheduledTask {
    private(set) var isCancelled = false
    private let onCancel: (@MainActor () -> Void)?
    init(onCancel: (@MainActor () -> Void)? = nil) { self.onCancel = onCancel }
    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        onCancel?()
    }
}

@MainActor
final class FakeScheduler: TimerScheduling {
    struct Entry {
        let date: Date
        let task: FakeTask
        let action: @MainActor @Sendable () -> Void
    }
    private(set) var entries: [Entry] = []
    var pending: [Entry] { entries.filter { !$0.task.isCancelled } }

    func schedule(at date: Date, _ action: @escaping @MainActor @Sendable () -> Void) -> any ScheduledTask {
        let task = FakeTask()
        entries.append(Entry(date: date, task: task, action: action))
        return task
    }

    /// Runs every pending action due at or before `date`, earliest first.
    func runDue(at date: Date) {
        let due = pending.filter { $0.date <= date }.sorted { $0.date < $1.date }
        for entry in due where !entry.task.isCancelled {
            entry.task.cancel()
            entry.action()
        }
    }
}
```

`Tests/EyesUpCoreTests/DeadlineMonitorTests.swift`:
```swift
import Foundation
import Testing
@testable import EyesUpCore

@Suite @MainActor struct DeadlineMonitorTests {
    let clock = FakeClock()
    let scheduler = FakeScheduler()

    func makeMonitor(lead: TimeInterval = 300) -> DeadlineMonitor {
        DeadlineMonitor(clock: clock, scheduler: scheduler, headsUpLead: lead)
    }

    @Test func armsTimerForEarliestDeadlineAndExpiresIt() {
        let monitor = makeMonitor()
        var expiredIDs: [UUID] = []
        monitor.onExpired = { expiredIDs = $0 }
        let soon = makeHold(end: .deadline(referenceDate.addingTimeInterval(60)))
        let later = makeHold(end: .deadline(referenceDate.addingTimeInterval(600)))
        monitor.update(holds: [soon, later])

        #expect(scheduler.pending.map(\.date).min() == referenceDate.addingTimeInterval(60))
        clock.advance(60)
        scheduler.runDue(at: clock.now)
        #expect(expiredIDs == [soon.id])
    }

    @Test func pastDeadlineExpiresImmediately() {
        let monitor = makeMonitor()
        var expiredIDs: [UUID] = []
        monitor.onExpired = { expiredIDs = $0 }
        clock.advance(3600) // e.g. the Mac slept through the deadline
        let hold = makeHold(end: .deadline(referenceDate.addingTimeInterval(60)))
        monitor.update(holds: [hold])
        #expect(expiredIDs == [hold.id])
    }

    @Test func graceExtendsExpiry() {
        let monitor = makeMonitor()
        monitor.update(holds: [makeHold(end: .deadline(referenceDate.addingTimeInterval(60)), grace: 120)])
        #expect(scheduler.pending.map(\.date).contains(referenceDate.addingTimeInterval(180)))
    }

    @Test func updateCancelsPreviousTimers() {
        let monitor = makeMonitor()
        monitor.update(holds: [makeHold(end: .deadline(referenceDate.addingTimeInterval(3600)))])
        let first = scheduler.entries.map(\.task)
        monitor.update(holds: [])
        #expect(first.allSatisfy(\.isCancelled))
        #expect(scheduler.pending.isEmpty)
    }

    @Test func headsUpFiresLeadTimeBeforeTheEnd() {
        let monitor = makeMonitor(lead: 300)
        var headsUpEnd: Date?
        monitor.onHeadsUp = { headsUpEnd = $0 }
        let end = referenceDate.addingTimeInterval(3600)
        monitor.update(holds: [makeHold(end: .deadline(end))])

        clock.advance(3300)
        scheduler.runDue(at: clock.now)
        #expect(headsUpEnd == end)
    }

    @Test func noHeadsUpWhenAnotherHoldHasNoEnd() {
        let monitor = makeMonitor()
        monitor.update(holds: [makeHold(end: .deadline(referenceDate.addingTimeInterval(3600))), makeHold(end: .indefinite)])
        #expect(!scheduler.pending.map(\.date).contains(referenceDate.addingTimeInterval(3300)))
    }

    @Test func noHeadsUpWhenLessThanLeadRemains() {
        let monitor = makeMonitor(lead: 300)
        monitor.update(holds: [makeHold(end: .deadline(referenceDate.addingTimeInterval(120)))])
        #expect(scheduler.pending.count == 1) // only the expiry timer
    }

    @Test func sameEndIsNotAnnouncedTwiceButAnExtendedEndIs() {
        let monitor = makeMonitor(lead: 300)
        var count = 0
        monitor.onHeadsUp = { _ in count += 1 }
        let hold = makeHold(end: .deadline(referenceDate.addingTimeInterval(3600)))
        monitor.update(holds: [hold])
        clock.advance(3300)
        scheduler.runDue(at: clock.now)
        monitor.update(holds: [hold])
        scheduler.runDue(at: clock.now)
        #expect(count == 1)

        var extended = hold
        extended.end = .deadline(referenceDate.addingTimeInterval(7200))
        monitor.update(holds: [extended])
        clock.advance(3600)
        scheduler.runDue(at: clock.now)
        #expect(count == 2)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter DeadlineMonitorTests`
Expected: FAIL to compile with `cannot find type 'WallClock' in scope`.

- [ ] **Step 3: Implement scheduling and the monitor**

`Sources/EyesUpCore/Engine/Scheduling.swift`:
```swift
import Foundation

public protocol WallClock: Sendable {
    var now: Date { get }
}

public struct SystemClock: WallClock {
    public init() {}
    public var now: Date { Date() }
}

@MainActor
public protocol ScheduledTask: AnyObject {
    func cancel()
}

@MainActor
public protocol TimerScheduling: AnyObject {
    func schedule(at date: Date, _ action: @escaping @MainActor @Sendable () -> Void) -> any ScheduledTask
}

/// One-shot timers on the main queue. Wall-clock deadlines keep counting while the Mac sleeps.
@MainActor
public final class DispatchTimerScheduler: TimerScheduling {
    public init() {}

    public func schedule(at date: Date, _ action: @escaping @MainActor @Sendable () -> Void) -> any ScheduledTask {
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(wallDeadline: .now() + max(0, date.timeIntervalSinceNow), leeway: .seconds(1))
        source.setEventHandler {
            source.cancel()
            MainActor.assumeIsolated { action() }
        }
        source.resume()
        return DispatchSourceTask(source)
    }
}

final class DispatchSourceTask: ScheduledTask {
    private let source: any DispatchSourceProtocol
    init(_ source: any DispatchSourceProtocol) { self.source = source }
    func cancel() { source.cancel() }
}
```

`Sources/EyesUpCore/Engine/DeadlineMonitor.swift`:
```swift
import Foundation

/// Arms exactly two timers: the earliest hold expiry, and the heads-up before the Mac may sleep.
@MainActor
public final class DeadlineMonitor {
    public var headsUpLead: TimeInterval
    public var onExpired: (([UUID]) -> Void)?
    public var onHeadsUp: ((Date) -> Void)?

    private let clock: any WallClock
    private let scheduler: any TimerScheduling
    private var holds: [Hold] = []
    private var expiryTask: (any ScheduledTask)?
    private var headsUpTask: (any ScheduledTask)?
    private var announcedEnd: Date?

    public init(clock: any WallClock, scheduler: any TimerScheduling, headsUpLead: TimeInterval = 300) {
        self.clock = clock
        self.scheduler = scheduler
        self.headsUpLead = headsUpLead
    }

    public func update(holds: [Hold]) {
        self.holds = holds
        expiryTask?.cancel()
        expiryTask = nil
        headsUpTask?.cancel()
        headsUpTask = nil

        let now = clock.now
        let expired = holds.filter { ($0.effectiveDeadline ?? .distantFuture) <= now }.map(\.id)
        if !expired.isEmpty {
            onExpired?(expired)
            return
        }

        if let next = holds.compactMap(\.effectiveDeadline).min() {
            expiryTask = scheduler.schedule(at: next) { [weak self] in self?.recheck() }
        }

        guard let end = Hold.awakeUntil(holds), end != announcedEnd else { return }
        let fireAt = end.addingTimeInterval(-headsUpLead)
        guard fireAt > now else { return }
        headsUpTask = scheduler.schedule(at: fireAt) { [weak self] in
            self?.announcedEnd = end
            self?.onHeadsUp?(end)
        }
    }

    private func recheck() {
        update(holds: holds)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter DeadlineMonitorTests`
Expected: 8 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/EyesUpCore/Engine Tests/EyesUpCoreTests
git commit -m "feat(core): add wall-clock scheduling and deadline monitor with heads-up" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: Process inspection and exit watching (PID-reuse safe)

**Files:**
- Create: `Sources/EyesUpCore/Processes/ProcessInspecting.swift`, `Sources/EyesUpCore/Processes/ProcessExitWatcher.swift`, `Tests/EyesUpCoreTests/ProcessTests.swift`
- Modify: `Tests/EyesUpCoreTests/Support/Fakes.swift` (append `FakeInspector`, `FakeExitWatcher`)

**Interfaces:**
- Consumes: `ProcessIdentity`, `ScheduledTask`, `DispatchSourceTask`.
- Produces:
  - `protocol ProcessInspecting: Sendable` with `identity(of: Int32) -> ProcessIdentity?` and `name(of: Int32) -> String?`.
  - `struct LibprocInspector`.
  - `@MainActor protocol ProcessExitWatching: AnyObject` with `watch(_ identity: ProcessIdentity, onExit: @escaping @MainActor @Sendable () -> Void) -> any ScheduledTask`.
  - `KqueueExitWatcher(inspector:)`.

- [ ] **Step 1: Write the fakes and the failing tests**

Append to `Tests/EyesUpCoreTests/Support/Fakes.swift`:
```swift
final class FakeInspector: ProcessInspecting, @unchecked Sendable {
    var identities: [Int32: ProcessIdentity] = [:]
    var names: [Int32: String] = [:]
    func identity(of pid: Int32) -> ProcessIdentity? { identities[pid] }
    func name(of pid: Int32) -> String? { names[pid] }
}

@MainActor
final class FakeExitWatcher: ProcessExitWatching {
    private(set) var watched: [ProcessIdentity: @MainActor @Sendable () -> Void] = [:]

    func watch(_ identity: ProcessIdentity, onExit: @escaping @MainActor @Sendable () -> Void) -> any ScheduledTask {
        watched[identity] = onExit
        return FakeTask { [weak self] in self?.watched[identity] = nil }
    }

    func simulateExit(_ identity: ProcessIdentity) {
        watched.removeValue(forKey: identity)?()
    }
}
```

`Tests/EyesUpCoreTests/ProcessTests.swift`:
```swift
import Foundation
import Testing
@testable import EyesUpCore

@Suite @MainActor struct ProcessTests {
    /// Polls while yielding the main actor, so main-queue callbacks can run.
    private func waitUntil(timeout: Duration = .seconds(3), _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func spawnSleep(_ seconds: String) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = [seconds]
        try process.run()
        return process
    }

    @Test func inspectorIdentifiesOwnProcessStably() {
        let inspector = LibprocInspector()
        let first = inspector.identity(of: getpid())
        #expect(first != nil)
        #expect(first == inspector.identity(of: getpid()))
        #expect(inspector.name(of: getpid())?.isEmpty == false)
    }

    @Test(arguments: [Int32(0), -1, Int32.max])
    func inspectorRejectsImpossiblePIDs(pid: Int32) {
        #expect(LibprocInspector().identity(of: pid) == nil)
        #expect(LibprocInspector().name(of: pid) == nil)
    }

    @Test func inspectorNamesAChildProcess() throws {
        let child = try spawnSleep("5")
        defer { child.terminate() }
        #expect(LibprocInspector().name(of: child.processIdentifier) == "sleep")
    }

    @Test func watcherFiresWhenProcessExits() async throws {
        let child = try spawnSleep("0.2")
        let inspector = LibprocInspector()
        let identity = try #require(inspector.identity(of: child.processIdentifier))
        var fired = false
        let task = KqueueExitWatcher(inspector: inspector).watch(identity) { fired = true }
        try await waitUntil { fired }
        #expect(fired)
        task.cancel()
    }

    @Test func watcherFiresForAlreadyExitedProcess() async throws {
        let child = try spawnSleep("0.2")
        let inspector = LibprocInspector()
        let identity = try #require(inspector.identity(of: child.processIdentifier))
        child.waitUntilExit()
        var fired = false
        let task = KqueueExitWatcher(inspector: inspector).watch(identity) { fired = true }
        try await waitUntil { fired }
        #expect(fired)
        task.cancel()
    }

    @Test func watcherTreatsRecycledPIDAsExited() async throws {
        // Our own PID is alive, but with a different start time it stands in for a recycled PID.
        let fake = FakeInspector()
        fake.identities[getpid()] = ProcessIdentity(pid: getpid(), startTime: 999)
        var fired = false
        let task = KqueueExitWatcher(inspector: fake).watch(ProcessIdentity(pid: getpid(), startTime: 1)) { fired = true }
        try await waitUntil { fired }
        #expect(fired)
        task.cancel()
    }

    @Test func cancelledWatchDoesNotFire() async throws {
        let child = try spawnSleep("0.3")
        let inspector = LibprocInspector()
        let identity = try #require(inspector.identity(of: child.processIdentifier))
        var fired = false
        let task = KqueueExitWatcher(inspector: inspector).watch(identity) { fired = true }
        task.cancel()
        child.waitUntilExit()
        try await Task.sleep(for: .milliseconds(300))
        #expect(!fired)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter ProcessTests`
Expected: FAIL to compile with `cannot find type 'ProcessInspecting' in scope`.

- [ ] **Step 3: Implement the inspector and watcher**

`Sources/EyesUpCore/Processes/ProcessInspecting.swift`:
```swift
import Darwin
import Foundation

public protocol ProcessInspecting: Sendable {
    func identity(of pid: Int32) -> ProcessIdentity?
    func name(of pid: Int32) -> String?
}

/// Reads process facts with libproc. It works without admin rights for the user's own processes.
public struct LibprocInspector: ProcessInspecting {
    public init() {}

    public func identity(of pid: Int32) -> ProcessIdentity? {
        guard let info = bsdInfo(pid) else { return nil }
        return ProcessIdentity(pid: pid, startTime: info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec)
    }

    public func name(of pid: Int32) -> String? {
        guard pid > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: 4096) // PROC_PIDPATHINFO_MAXSIZE
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        if length > 0 {
            let bytes = buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }
            return URL(fileURLWithPath: String(decoding: bytes, as: UTF8.self)).lastPathComponent
        }
        guard let info = bsdInfo(pid) else { return nil }
        let comm = withUnsafeBytes(of: info.pbi_comm) { raw in Array(raw.prefix { $0 != 0 }) }
        return comm.isEmpty ? nil : String(decoding: comm, as: UTF8.self)
    }

    private func bsdInfo(_ pid: Int32) -> proc_bsdinfo? {
        guard pid > 0 else { return nil }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return info
    }
}
```

`Sources/EyesUpCore/Processes/ProcessExitWatcher.swift`:
```swift
import Foundation

@MainActor
public protocol ProcessExitWatching: AnyObject {
    func watch(_ identity: ProcessIdentity, onExit: @escaping @MainActor @Sendable () -> Void) -> any ScheduledTask
}

/// Kernel-notified process exit (kqueue NOTE_EXIT): no polling.
@MainActor
public final class KqueueExitWatcher: ProcessExitWatching {
    private let inspector: any ProcessInspecting

    public init(inspector: any ProcessInspecting) {
        self.inspector = inspector
    }

    public func watch(_ identity: ProcessIdentity, onExit: @escaping @MainActor @Sendable () -> Void) -> any ScheduledTask {
        let source = DispatchSource.makeProcessSource(identifier: identity.pid, eventMask: .exit, queue: .main)
        source.setEventHandler {
            source.cancel()
            MainActor.assumeIsolated { onExit() }
        }
        source.resume()

        // Already gone, or the PID now belongs to a different process: end the hold right away.
        if inspector.identity(of: identity.pid) != identity {
            source.cancel()
            DispatchQueue.main.async { MainActor.assumeIsolated { onExit() } }
        }
        return DispatchSourceTask(source)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter ProcessTests`
Expected: 9 tests pass (the `inspectorRejectsImpossiblePIDs` test counts once per argument).

- [ ] **Step 5: Commit**

```bash
git add Sources/EyesUpCore/Processes Tests/EyesUpCoreTests
git commit -m "feat(core): add PID-reuse-safe process inspection and kqueue exit watching" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 7: JSON store with corrupt-file recovery, and hold restore rules

**Files:**
- Create: `Sources/EyesUpCore/Store/JSONFileStore.swift`, `Sources/EyesUpCore/Store/HoldRestorer.swift`, `Tests/EyesUpCoreTests/StoreTests.swift`

**Interfaces:**
- Consumes: `Hold`, `ProcessInspecting`.
- Produces:
  - `enum StoreLoadResult<Value> { case missing, loaded(Value), corrupt(movedTo: URL?) }`.
  - `struct JSONFileStore<Value: Codable & Sendable>` with `init(url:schemaVersion:)`, `load(now:) -> StoreLoadResult<Value>`, `save(_:) throws`, and `static var maxFileSize: Int` (5 MB).
  - `enum StorageLocation { static var directory: URL }`.
  - `enum HoldRestorer { static func restorable(_:now:inspector:) -> [Hold] }`.

- [ ] **Step 1: Write the failing tests**

`Tests/EyesUpCoreTests/StoreTests.swift`:
```swift
import Foundation
import Testing
@testable import EyesUpCore

@Suite struct StoreTests {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("EyesUpTests-\(UUID().uuidString)")
    var url: URL { directory.appendingPathComponent("holds.json") }
    var store: JSONFileStore<[Hold]> { JSONFileStore(url: url, schemaVersion: 1) }

    private func write(_ text: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func assertMovedAside(_ result: StoreLoadResult<[Hold]>) {
        guard case .corrupt(let moved) = result else {
            Issue.record("expected .corrupt, got \(result)")
            return
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(moved.map { FileManager.default.fileExists(atPath: $0.path) } == true)
        #expect(moved?.lastPathComponent.hasPrefix("holds.corrupt-") == true)
    }

    @Test func missingFileLoadsAsMissing() {
        guard case .missing = store.load() else { Issue.record("expected .missing"); return }
    }

    @Test func roundTripsHolds() throws {
        let holds = [makeHold(label: "A"), makeHold(label: "B", end: .deadline(referenceDate))]
        try store.save(holds)
        guard case .loaded(let loaded) = store.load() else { Issue.record("expected .loaded"); return }
        #expect(loaded == holds)
    }

    @Test func corruptFileIsMovedAside() throws {
        try write("this is not json")
        assertMovedAside(store.load(now: referenceDate))
    }

    @Test func truncatedFileIsMovedAside() throws {
        try store.save([makeHold()])
        let data = try Data(contentsOf: url)
        try data.prefix(data.count / 2).write(to: url)
        assertMovedAside(store.load(now: referenceDate))
    }

    @Test func futureSchemaIsMovedAside() throws {
        try JSONFileStore<[Hold]>(url: url, schemaVersion: 99).save([makeHold()])
        assertMovedAside(store.load(now: referenceDate))
    }

    @Test func oversizedFileIsMovedAside() throws {
        try write(String(repeating: " ", count: JSONFileStore<[Hold]>.maxFileSize + 1))
        assertMovedAside(store.load(now: referenceDate))
    }

    @Test func restoreRules() {
        let now = referenceDate
        let inspector = FakeInspector()
        let alive = ProcessIdentity(pid: 10, startTime: 1)
        inspector.identities[10] = alive
        inspector.identities[11] = ProcessIdentity(pid: 11, startTime: 999)

        let keepIndefinite = makeHold(end: .indefinite)
        let keepFuture = makeHold(end: .deadline(now.addingTimeInterval(60)))
        let keepInGrace = makeHold(end: .deadline(now.addingTimeInterval(-30)), grace: 60)
        let dropPast = makeHold(end: .deadline(now.addingTimeInterval(-1)))
        let keepAlive = makeHold(end: .processExit(alive))
        let dropRecycled = makeHold(end: .processExit(ProcessIdentity(pid: 11, startTime: 1)))
        let dropGone = makeHold(end: .processExit(ProcessIdentity(pid: 12, startTime: 1)))
        let dropTrigger = makeHold(end: .triggerControlled, source: .trigger(UUID()))

        let restored = HoldRestorer.restorable(
            [keepIndefinite, keepFuture, keepInGrace, dropPast, keepAlive, dropRecycled, dropGone, dropTrigger],
            now: now, inspector: inspector
        )
        #expect(restored.map(\.id) == [keepIndefinite.id, keepFuture.id, keepInGrace.id, keepAlive.id])
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter StoreTests`
Expected: FAIL to compile with `cannot find type 'JSONFileStore' in scope`.

- [ ] **Step 3: Implement the store and restorer**

`Sources/EyesUpCore/Store/JSONFileStore.swift`:
```swift
import Foundation

public enum StoreLoadResult<Value> {
    case missing
    case loaded(Value)
    /// The file was unreadable. It was moved to `movedTo` (nil if moving failed and it was deleted).
    case corrupt(movedTo: URL?)
}

extension StoreLoadResult: Sendable where Value: Sendable {}

/// A versioned JSON file, written atomically. Bad files are moved aside, never crashed on.
public struct JSONFileStore<Value: Codable & Sendable>: Sendable {
    public static var maxFileSize: Int { 5 * 1024 * 1024 }

    public let url: URL
    public let schemaVersion: Int

    private struct Envelope: Codable {
        var schemaVersion: Int
        var value: Value
    }

    public init(url: URL, schemaVersion: Int) {
        self.url = url
        self.schemaVersion = schemaVersion
    }

    public func load(now: Date = Date()) -> StoreLoadResult<Value> {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return .missing }

        if let size = (try? fileManager.attributesOfItem(atPath: url.path))?[.size] as? Int, size > Self.maxFileSize {
            return .corrupt(movedTo: moveAside(now: now))
        }
        guard let data = try? Data(contentsOf: url),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.schemaVersion == schemaVersion else {
            return .corrupt(movedTo: moveAside(now: now))
        }
        return .loaded(envelope.value)
    }

    public func save(_ value: Value) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Envelope(schemaVersion: schemaVersion, value: value)).write(to: url, options: .atomic)
    }

    private func moveAside(now: Date) -> URL? {
        let stem = url.deletingPathExtension().lastPathComponent
        let target = url.deletingLastPathComponent()
            .appendingPathComponent("\(stem).corrupt-\(Int(now.timeIntervalSince1970)).json")
        do {
            try FileManager.default.moveItem(at: url, to: target)
            return target
        } catch {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }
}

public enum StorageLocation {
    /// ~/Library/Application Support/EyesUpGuardian
    public static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EyesUpGuardian", isDirectory: true)
    }
}
```

`Sources/EyesUpCore/Store/HoldRestorer.swift`:
```swift
import Foundation

/// Spec §4.4: which saved holds survive a relaunch.
public enum HoldRestorer {
    public static func restorable(_ holds: [Hold], now: Date, inspector: any ProcessInspecting) -> [Hold] {
        holds.filter { hold in
            switch hold.end {
            case .indefinite:
                return true
            case .deadline:
                return (hold.effectiveDeadline ?? now) > now
            case .processExit(let identity):
                return inspector.identity(of: identity.pid) == identity
            case .triggerControlled:
                return false
            }
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter StoreTests`
Expected: 7 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/EyesUpCore/Store Tests/EyesUpCoreTests/StoreTests.swift
git commit -m "feat(core): add versioned JSON store with corrupt-file recovery and hold restore rules" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 8: AwakeController (the single entry point the UI talks to)

**Files:**
- Create: `Sources/EyesUpCore/AwakeController.swift`, `Tests/EyesUpCoreTests/AwakeControllerTests.swift`

**Interfaces:**
- Consumes:
  - `AwakeEngine`, `PowerAssertionProviding`;
  - `DeadlineMonitor`, `WallClock`, `TimerScheduling`;
  - `ProcessExitWatching`, `ProcessInspecting`;
  - `JSONFileStore<[Hold]>`, `HoldRestorer`, `TimeFormatting`.
- Produces:
  - `enum AwakeError: Error` with cases `invalidDuration`, `dateInPast`, `invalidPID`, `noSuchProcess`, `ownProcess`, and `var message: String`.
  - `@MainActor @Observable final class AwakeController`:
    - Init: `init(provider:clock:scheduler:exitWatcher:inspector:holdStore:headsUpLead:ownPID:)`.
    - Read-only state: `holds`, `lastError`, `storeNotice`, `isAwake`, `awakeUntil`, `sessionStart`, `displayOn`, `currentPolicy`.
    - Starting holds (all `@discardableResult`): `startTimer(duration:policy:) throws -> Hold`, `startIndefinite(policy:) -> Hold`, `startUntil(_:policy:) throws -> Hold`, `watchProcess(pid:policy:grace:) throws -> Hold`.
    - Changing holds: `extend(by:policy:) throws`, `setDisplayOn(_:)`, `stop(id:)`, `stopAll()`.
    - Other: `nudgeDisplay()`, `restore()`, `refresh()`, `shutdown()`, `setHeadsUpHandler(_:)`, `static parsePID(_:) throws -> Int32`, `static maxManualDuration`.

**Behavior decisions (spec clarifications, recorded here):**
- **Starting a manual session replaces the old one.** "Manual session" means a timer, an until-time, or indefinite; clicking a new one replaces the current one. Process holds and trigger holds are never replaced.
- **"+30m" (extend)** adds time to every non-trigger deadline hold and relabels it "Until <time>". If there is none, it starts a new timer.
- **Deliberate Quit** (`shutdown()`) stops all holds and saves an empty list. Only a crash or kill leaves holds to restore on the next launch.

- [ ] **Step 1: Write the failing tests**

`Tests/EyesUpCoreTests/AwakeControllerTests.swift`:
```swift
import Foundation
import Testing
@testable import EyesUpCore

@Suite @MainActor struct AwakeControllerTests {
    let provider = FakePowerAssertions()
    let clock = FakeClock()
    let scheduler = FakeScheduler()
    let watcher = FakeExitWatcher()
    let inspector = FakeInspector()
    let ownPID: Int32 = 777

    func makeController(store: JSONFileStore<[Hold]>? = nil) -> AwakeController {
        AwakeController(
            provider: provider, clock: clock, scheduler: scheduler, exitWatcher: watcher,
            inspector: inspector, holdStore: store, headsUpLead: 300, ownPID: ownPID
        )
    }

    func tempStore() -> JSONFileStore<[Hold]> {
        JSONFileStore(
            url: FileManager.default.temporaryDirectory.appendingPathComponent("EyesUpTests-\(UUID().uuidString)/holds.json"),
            schemaVersion: 1
        )
    }

    // MARK: Timers and sessions

    @Test func startTimerKeepsMacAwakeUntilDeadline() throws {
        let controller = makeController()
        let hold = try controller.startTimer(duration: 7200, policy: .system)
        #expect(hold.label == "Timer 2h")
        #expect(controller.awakeUntil == referenceDate.addingTimeInterval(7200))
        #expect(provider.liveNames == ["EyesUpGuardian: Timer 2h"])

        clock.advance(7200)
        scheduler.runDue(at: clock.now)
        #expect(controller.holds.isEmpty)
        #expect(provider.live.isEmpty)
    }

    @Test(arguments: [0.0, -5.0, AwakeController.maxManualDuration + 1])
    func startTimerRejectsBadDurations(seconds: Double) {
        let controller = makeController()
        #expect(throws: AwakeError.invalidDuration) { try controller.startTimer(duration: seconds, policy: .system) }
        #expect(controller.holds.isEmpty)
    }

    @Test func newManualSessionReplacesThePreviousOne() throws {
        let controller = makeController()
        try controller.startTimer(duration: 3600, policy: .system)
        try controller.startTimer(duration: 7200, policy: .system)
        #expect(controller.holds.map(\.label) == ["Timer 2h"])
        controller.startIndefinite(policy: .system)
        #expect(controller.holds.map(\.label) == ["Indefinitely"])
        #expect(controller.awakeUntil == nil)
    }

    @Test func startUntilRejectsPastTimes() {
        let controller = makeController()
        #expect(throws: AwakeError.dateInPast) { try controller.startUntil(referenceDate.addingTimeInterval(-60), policy: .system) }
        #expect(throws: AwakeError.dateInPast) { try controller.startUntil(referenceDate, policy: .system) }
    }

    @Test func startUntilLabelsWithTheTime() throws {
        let controller = makeController()
        let hold = try controller.startUntil(referenceDate.addingTimeInterval(3600), policy: .system)
        #expect(hold.label.hasPrefix("Until "))
        #expect(controller.awakeUntil == referenceDate.addingTimeInterval(3600))
    }

    @Test func extendAddsTimeToTimers() throws {
        let controller = makeController()
        try controller.startTimer(duration: 3600, policy: .system)
        try controller.extend(by: 1800, policy: .system)
        #expect(controller.awakeUntil == referenceDate.addingTimeInterval(5400))
        #expect(controller.holds.first?.label.hasPrefix("Until ") == true)
    }

    @Test func extendWithNoTimerStartsOne() throws {
        let controller = makeController()
        try controller.extend(by: 1800, policy: .system)
        #expect(controller.holds.map(\.label) == ["Timer 30m"])
    }

    // MARK: Processes

    @Test func watchProcessHoldsUntilExit() throws {
        let identity = ProcessIdentity(pid: 4242, startTime: 5)
        inspector.identities[4242] = identity
        inspector.names[4242] = "swift-build"
        let controller = makeController()

        let hold = try controller.watchProcess(pid: 4242, policy: .system)
        #expect(hold.label == "PID 4242 · swift-build")
        #expect(watcher.watched[identity] != nil)

        watcher.simulateExit(identity)
        #expect(controller.holds.isEmpty)
        #expect(provider.live.isEmpty)
    }

    @Test func processGraceKeepsMacAwakeAfterExit() throws {
        let identity = ProcessIdentity(pid: 4242, startTime: 5)
        inspector.identities[4242] = identity
        let controller = makeController()
        try controller.watchProcess(pid: 4242, policy: .system, grace: 300)

        watcher.simulateExit(identity)
        #expect(controller.awakeUntil == referenceDate.addingTimeInterval(300))
        clock.advance(300)
        scheduler.runDue(at: clock.now)
        #expect(controller.holds.isEmpty)
    }

    @Test func watchProcessRejectsMissingProcess() {
        let controller = makeController()
        #expect(throws: AwakeError.noSuchProcess) { try controller.watchProcess(pid: 4242, policy: .system) }
    }

    @Test func watchProcessRejectsOwnAndInvalidPIDs() {
        let controller = makeController()
        #expect(throws: AwakeError.ownProcess) { try controller.watchProcess(pid: ownPID, policy: .system) }
        #expect(throws: AwakeError.invalidPID) { try controller.watchProcess(pid: 0, policy: .system) }
        #expect(throws: AwakeError.invalidPID) { try controller.watchProcess(pid: -3, policy: .system) }
    }

    @Test(arguments: ["", "abc", "-5", "0", "99999999999", "12 34", "٣", "12a", "+12", "1e3"])
    func parsePIDRejectsGarbage(text: String) {
        #expect(throws: AwakeError.invalidPID) { try AwakeController.parsePID(text) }
    }

    @Test func parsePIDAcceptsDigitsWithSurroundingSpaces() throws {
        #expect(try AwakeController.parsePID(" 4242 ") == 4242)
    }

    @Test func stoppingAProcessHoldCancelsItsWatch() throws {
        let identity = ProcessIdentity(pid: 4242, startTime: 5)
        inspector.identities[4242] = identity
        let controller = makeController()
        let hold = try controller.watchProcess(pid: 4242, policy: .system)
        controller.stop(id: hold.id)
        #expect(watcher.watched.isEmpty)
    }

    // MARK: Overlaps, display, nudge

    @Test func stoppingOneOverlappingHoldKeepsMacAwake() throws {
        let identity = ProcessIdentity(pid: 4242, startTime: 5)
        inspector.identities[4242] = identity
        let controller = makeController()
        let timer = try controller.startTimer(duration: 3600, policy: .system)
        try controller.watchProcess(pid: 4242, policy: .system)

        controller.stop(id: timer.id)
        #expect(provider.liveKinds == [.preventIdleSystemSleep])

        controller.stopAll()
        #expect(controller.holds.isEmpty)
        #expect(provider.live.isEmpty)
    }

    @Test func displayToggleAddsAndRemovesDisplayAssertion() throws {
        let controller = makeController()
        try controller.startTimer(duration: 3600, policy: .system)
        controller.setDisplayOn(true)
        #expect(controller.displayOn)
        #expect(provider.liveKinds == [.preventIdleSystemSleep, .preventDisplaySleep])
        controller.setDisplayOn(false)
        #expect(provider.liveKinds == [.preventIdleSystemSleep])
    }

    @Test func nudgeDeclaresUserActivity() {
        let controller = makeController()
        controller.nudgeDisplay()
        #expect(provider.userActivityCount == 1)
    }

    @Test func assertionFailureIsSurfaced() throws {
        provider.failingKinds = [.preventIdleSystemSleep]
        let controller = makeController()
        try controller.startTimer(duration: 60, policy: .system)
        #expect(controller.lastError?.kind == .preventIdleSystemSleep)
    }

    // MARK: Heads-up

    @Test func headsUpHandlerIsCalledBeforeTheEnd() throws {
        let controller = makeController()
        var announced: Date?
        controller.setHeadsUpHandler { announced = $0 }
        try controller.startTimer(duration: 3600, policy: .system)
        clock.advance(3300)
        scheduler.runDue(at: clock.now)
        #expect(announced == referenceDate.addingTimeInterval(3600))
    }

    // MARK: Persistence

    @Test func holdsSurviveARestart() throws {
        let store = tempStore()
        let first = makeController(store: store)
        first.startIndefinite(policy: .system)

        let second = makeController(store: store)
        second.restore()
        #expect(second.holds.map(\.label) == ["Indefinitely"])
        #expect(second.isAwake)
    }

    @Test func restoreReportsCorruptStore() throws {
        let store = tempStore()
        try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("garbage".utf8).write(to: store.url)
        let controller = makeController(store: store)
        controller.restore()
        #expect(controller.holds.isEmpty)
        #expect(controller.storeNotice != nil)
    }

    @Test func shutdownStopsEverythingAndSavesEmpty() throws {
        let store = tempStore()
        let controller = makeController(store: store)
        controller.startIndefinite(policy: .system)
        controller.shutdown()
        #expect(provider.live.isEmpty)
        guard case .loaded(let saved) = store.load() else { Issue.record("expected saved file"); return }
        #expect(saved.isEmpty)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter AwakeControllerTests`
Expected: FAIL to compile with `cannot find 'AwakeController' in scope`.

- [ ] **Step 3: Implement the controller**

`Sources/EyesUpCore/AwakeController.swift`:
```swift
import Foundation
import Observation

public enum AwakeError: Error, Equatable, Sendable {
    case invalidDuration
    case dateInPast
    case invalidPID
    case noSuchProcess
    case ownProcess

    public var message: String {
        switch self {
        case .invalidDuration: "Choose a duration between 1 minute and 999 hours."
        case .dateInPast: "That time has already passed."
        case .invalidPID: "Enter a process ID using digits only, like 48213."
        case .noSuchProcess: "No running process has that ID."
        case .ownProcess: "EyesUpGuardian can't watch itself."
        }
    }
}

/// Owns the list of holds (the spec's hold registry) and keeps the engine, timers and watchers in sync with it.
@MainActor
@Observable
public final class AwakeController {
    public nonisolated static let maxManualDuration: TimeInterval = 999 * 3600

    public private(set) var holds: [Hold] = []
    public private(set) var lastError: PowerAssertionError?
    public private(set) var storeNotice: String?

    public var isAwake: Bool { !holds.isEmpty }
    public var awakeUntil: Date? { Hold.awakeUntil(holds) }
    public var sessionStart: Date? { holds.map(\.createdAt).min() }
    public var displayOn: Bool { holds.contains { !$0.source.isTrigger && $0.policy.contains(.display) } }
    /// The policy "+30m" and notification actions should use for new holds.
    public var currentPolicy: SleepPolicy { displayOn ? [.system, .display] : .system }

    @ObservationIgnored private let provider: any PowerAssertionProviding
    @ObservationIgnored private let engine: AwakeEngine
    @ObservationIgnored private let deadlines: DeadlineMonitor
    @ObservationIgnored private let exitWatcher: any ProcessExitWatching
    @ObservationIgnored private let inspector: any ProcessInspecting
    @ObservationIgnored private let clock: any WallClock
    @ObservationIgnored private let holdStore: JSONFileStore<[Hold]>?
    @ObservationIgnored private let ownPID: Int32
    @ObservationIgnored private var watches: [UUID: any ScheduledTask] = [:]

    public init(
        provider: any PowerAssertionProviding,
        clock: any WallClock = SystemClock(),
        scheduler: any TimerScheduling,
        exitWatcher: any ProcessExitWatching,
        inspector: any ProcessInspecting,
        holdStore: JSONFileStore<[Hold]>? = nil,
        headsUpLead: TimeInterval = 300,
        ownPID: Int32 = getpid()
    ) {
        self.provider = provider
        self.clock = clock
        self.exitWatcher = exitWatcher
        self.inspector = inspector
        self.holdStore = holdStore
        self.ownPID = ownPID
        engine = AwakeEngine(provider: provider)
        deadlines = DeadlineMonitor(clock: clock, scheduler: scheduler, headsUpLead: headsUpLead)
        deadlines.onExpired = { [weak self] ids in self?.remove(ids: Set(ids)) }
    }

    // MARK: Starting

    @discardableResult
    public func startTimer(duration: TimeInterval, policy: SleepPolicy) throws -> Hold {
        guard duration > 0, duration <= Self.maxManualDuration else { throw AwakeError.invalidDuration }
        let now = clock.now
        return replaceManualSession(with: Hold(
            label: "Timer \(TimeFormatting.duration(duration))", policy: policy,
            end: .deadline(now.addingTimeInterval(duration)), createdAt: now
        ))
    }

    @discardableResult
    public func startIndefinite(policy: SleepPolicy) -> Hold {
        replaceManualSession(with: Hold(label: "Indefinitely", policy: policy, end: .indefinite, createdAt: clock.now))
    }

    @discardableResult
    public func startUntil(_ date: Date, policy: SleepPolicy) throws -> Hold {
        let now = clock.now
        guard date > now else { throw AwakeError.dateInPast }
        guard date.timeIntervalSince(now) <= Self.maxManualDuration else { throw AwakeError.invalidDuration }
        return replaceManualSession(with: Hold(label: Self.untilLabel(date), policy: policy, end: .deadline(date), createdAt: now))
    }

    @discardableResult
    public func watchProcess(pid: Int32, policy: SleepPolicy, grace: TimeInterval? = nil) throws -> Hold {
        guard pid > 0 else { throw AwakeError.invalidPID }
        guard pid != ownPID else { throw AwakeError.ownProcess }
        guard let identity = inspector.identity(of: pid) else { throw AwakeError.noSuchProcess }
        let name = String((inspector.name(of: pid) ?? "process").prefix(40))
        let hold = Hold(label: "PID \(pid) · \(name)", policy: policy, end: .processExit(identity), grace: grace, createdAt: clock.now)
        holds.append(hold)
        commit()
        return hold
    }

    /// Validates user-typed PIDs: ASCII digits only, 1...Int32.max.
    public nonisolated static func parsePID(_ text: String) throws -> Int32 {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 10,
              trimmed.unicodeScalars.allSatisfy({ ("0"..."9").contains($0) }),
              let pid = Int32(trimmed), pid > 0 else { throw AwakeError.invalidPID }
        return pid
    }

    // MARK: Changing

    public func extend(by seconds: TimeInterval, policy: SleepPolicy) throws {
        guard seconds > 0, seconds <= Self.maxManualDuration else { throw AwakeError.invalidDuration }
        var extended = false
        for index in holds.indices where !holds[index].source.isTrigger {
            guard case .deadline(let date) = holds[index].end else { continue }
            let newDate = date.addingTimeInterval(seconds)
            holds[index].end = .deadline(newDate)
            holds[index].label = Self.untilLabel(newDate)
            extended = true
        }
        if extended { commit() } else { try startTimer(duration: seconds, policy: policy) }
    }

    public func setDisplayOn(_ on: Bool) {
        for index in holds.indices where !holds[index].source.isTrigger {
            if on { holds[index].policy.insert(.display) } else { holds[index].policy.remove(.display) }
        }
        commit()
    }

    public func stop(id: UUID) {
        remove(ids: [id])
    }

    public func stopAll() {
        remove(ids: Set(holds.filter { !$0.source.isTrigger }.map(\.id)))
    }

    /// caffeinate -u
    public func nudgeDisplay() {
        provider.declareUserActivity(name: "EyesUpGuardian: nudge display")
    }

    // MARK: Lifecycle

    public func restore() {
        if let holdStore {
            switch holdStore.load(now: clock.now) {
            case .missing:
                break
            case .loaded(let saved):
                holds = HoldRestorer.restorable(saved, now: clock.now, inspector: inspector)
            case .corrupt:
                storeNotice = "Saved keep-awake sessions couldn't be read, so they were reset."
            }
        }
        commit()
    }

    /// Re-evaluate after wake or a clock change so passed deadlines end immediately.
    public func refresh() {
        commit()
    }

    /// Deliberate quit: stop everything and remember nothing.
    public func shutdown() {
        holds.removeAll()
        commit()
    }

    public func setHeadsUpHandler(_ handler: @escaping (Date) -> Void) {
        deadlines.onHeadsUp = handler
    }

    // MARK: Private

    private func replaceManualSession(with hold: Hold) -> Hold {
        holds.removeAll(where: \.isManualSession)
        holds.append(hold)
        commit()
        return hold
    }

    private func remove(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        holds.removeAll { ids.contains($0.id) }
        commit()
    }

    private func processExited(holdID: UUID) {
        watches[holdID] = nil
        guard let index = holds.firstIndex(where: { $0.id == holdID }) else { return }
        if let grace = holds[index].grace, grace > 0 {
            holds[index].end = .deadline(clock.now.addingTimeInterval(grace))
            holds[index].grace = nil
            holds[index].label += " · exited"
            commit()
        } else {
            remove(ids: [holdID])
        }
    }

    private func commit() {
        engine.reconcile(holds: holds)
        lastError = engine.lastError
        syncWatches()
        persist()
        deadlines.update(holds: holds)
    }

    private func syncWatches() {
        var wanted: [UUID: ProcessIdentity] = [:]
        for hold in holds {
            if case .processExit(let identity) = hold.end { wanted[hold.id] = identity }
        }
        for (id, task) in watches where wanted[id] == nil {
            task.cancel()
            watches[id] = nil
        }
        for (id, identity) in wanted where watches[id] == nil {
            watches[id] = exitWatcher.watch(identity) { [weak self] in self?.processExited(holdID: id) }
        }
    }

    private func persist() {
        guard let holdStore else { return }
        do {
            try holdStore.save(holds)
        } catch {
            storeNotice = "Couldn't save keep-awake sessions: \(error.localizedDescription)"
        }
    }

    private static func untilLabel(_ date: Date) -> String {
        "Until " + date.formatted(date: .omitted, time: .shortened)
    }
}
```

`deadlines.update` runs last in `commit()` because it may call `onExpired` synchronously. That triggers a nested `commit()` with the already-shortened list, so everything before it must be finished first.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter AwakeControllerTests`
Expected: every `AwakeControllerTests` case passes.

Run: `swift test`
Expected: the whole suite passes.

- [ ] **Step 5: Commit**

```bash
git add Sources/EyesUpCore/AwakeController.swift Tests/EyesUpCoreTests/AwakeControllerTests.swift
git commit -m "feat(core): add AwakeController tying holds, engine, deadlines, watchers and storage together" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 9: Security guard tests (no commands, no network, no dependencies)

**Files:**
- Create: `Tests/EyesUpCoreTests/SecurityGuardTests.swift`

**Interfaces:**
- Consumes: the repo's `Sources/` tree and `Package.swift`, read as text.
- Produces: a test that fails the build if any forbidden API from spec §9 appears in app code.

- [ ] **Step 1: Write the tests**

`Tests/EyesUpCoreTests/SecurityGuardTests.swift`:
```swift
import Foundation
import Testing

/// Spec §9: app code must never run commands, open network connections, escalate privileges, or add dependencies.
@Suite struct SecurityGuardTests {
    static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // EyesUpCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // package root

    static let forbidden: [(pattern: String, reason: String)] = [
        (#"\bProcess\s*\("#, "launching processes"),
        (#"\bNSTask\b"#, "launching processes"),
        (#"\bposix_spawn"#, "launching processes"),
        (#"\bpopen\s*\("#, "launching processes"),
        (#"\bsystem\s*\("#, "launching processes"),
        (#"\bexec(l|lp|le|v|vp|ve)\s*\("#, "launching processes"),
        (#"NSAppleScript|OSAScript"#, "running scripts"),
        (#"\bURLSession\b"#, "network access"),
        (#"\bNWConnection\b|\bNWListener\b|import\s+Network\b"#, "network access"),
        (#"\bsocket\s*\("#, "network access"),
        (#"AuthorizationExecuteWithPrivileges|AuthorizationCreate|SMJobBless"#, "privilege escalation"),
        (#"\bsudo\b"#, "privilege escalation"),
    ]

    static func violations(in text: String) throws -> [String] {
        try forbidden.compactMap { rule in
            try text.firstMatch(of: Regex(rule.pattern)) == nil ? nil : rule.reason
        }
    }

    @Test func guardDetectsViolations() throws {
        #expect(try Self.violations(in: "let p = Process()") == ["launching processes"])
        #expect(try Self.violations(in: "URLSession.shared") == ["network access"])
        #expect(try Self.violations(in: "let id = ProcessIdentity(pid: 1, startTime: 2)").isEmpty)
    }

    @Test func sourcesContainNoForbiddenAPIs() throws {
        let sources = Self.packageRoot.appendingPathComponent("Sources")
        let enumerator = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        let files = enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        #expect(!files.isEmpty)
        for file in files {
            let found = try Self.violations(in: String(contentsOf: file, encoding: .utf8))
            #expect(found.isEmpty, "\(file.lastPathComponent) uses a forbidden API: \(found)")
        }
    }

    @Test func packageHasNoDependencies() throws {
        let manifest = try String(contentsOf: Self.packageRoot.appendingPathComponent("Package.swift"), encoding: .utf8)
        #expect(!manifest.contains(".package("))
    }
}
```

- [ ] **Step 2: Run the tests**

Run: `swift test --filter SecurityGuardTests`
Expected: 3 tests pass.

- [ ] **Step 3: Prove the guard catches a real violation**

Temporarily add `let _ = URLSession.shared` to the end of `Sources/EyesUpCore/EyesUpCore.swift`.
Run: `swift test --filter SecurityGuardTests`
Expected: `sourcesContainNoForbiddenAPIs` FAILS, naming `EyesUpCore.swift` and `network access`.
Revert the line, then confirm with `git diff --exit-code Sources`, which should print nothing.

- [ ] **Step 4: Commit**

```bash
git add Tests/EyesUpCoreTests/SecurityGuardTests.swift
git commit -m "test: guard against command execution, networking, privilege escalation and dependencies" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 10: Menu-bar item: draining ring, time readout, right-click menu, wake handling

**Files:**
- Create: `Sources/EyesUpApp/AppEnvironment.swift`, `Sources/EyesUpApp/MenuBar/RingIcon.swift`, `Sources/EyesUpApp/MenuBar/StatusItemController.swift`
- Modify (replace entirely): `Sources/EyesUpApp/EyesUpGuardianApp.swift`

**Interfaces:**
- Consumes: `AwakeController` (all of Task 8), `IOKitPowerAssertions`, `DispatchTimerScheduler`, `KqueueExitWatcher`, `LibprocInspector`, `JSONFileStore`, `StorageLocation`, `TimeFormatting`.
- Produces:
  - `AppEnvironment` with `controller`, `start()`, `shutdown()`.
  - `enum Defaults` with `presets`, `headsUpLead`, `extendStep`.
  - `RingIcon.image(active:fraction:) -> NSImage`.
  - `StatusItemController(controller:)` with `refresh()` and `setPopoverContent(_:)`. Task 11 uses `setPopoverContent(_:)`.

- [ ] **Step 1: Write the environment and app entry**

`Sources/EyesUpApp/AppEnvironment.swift`:
```swift
import AppKit
import EyesUpCore

enum Defaults {
    static let presets: [TimeInterval] = [900, 3600, 7200, 14400]
    static let headsUpLead: TimeInterval = 300
    static let extendStep: TimeInterval = 1800
}

/// Builds the real dependencies and connects system events to the controller.
@MainActor
final class AppEnvironment {
    let controller: AwakeController
    private var observers: [NSObjectProtocol] = []

    init() {
        let inspector = LibprocInspector()
        controller = AwakeController(
            provider: IOKitPowerAssertions(),
            scheduler: DispatchTimerScheduler(),
            exitWatcher: KqueueExitWatcher(inspector: inspector),
            inspector: inspector,
            holdStore: JSONFileStore(url: StorageLocation.directory.appendingPathComponent("holds.json"), schemaVersion: 1),
            headsUpLead: Defaults.headsUpLead
        )
    }

    func start() {
        controller.restore()
        let refresh: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.controller.refresh() }
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: refresh))
        observers.append(NotificationCenter.default.addObserver(
            forName: .NSSystemClockDidChange, object: nil, queue: .main, using: refresh))
    }

    func shutdown() {
        controller.shutdown()
    }
}
```

`Sources/EyesUpApp/EyesUpGuardianApp.swift` (replaces the Task 1 placeholder):
```swift
import AppKit
import SwiftUI

@main
struct EyesUpGuardianApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene { Settings { EmptyView() } }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var environment: AppEnvironment?
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let environment = AppEnvironment()
        environment.start()
        statusItem = StatusItemController(controller: environment.controller)
        self.environment = environment
    }

    func applicationWillTerminate(_ notification: Notification) {
        environment?.shutdown()
    }
}
```

- [ ] **Step 2: Write the ring icon**

`Sources/EyesUpApp/MenuBar/RingIcon.swift`:
```swift
import AppKit

/// Menu-bar glyph. The arc drains as the session runs down; a full ring means no end time; a faint ring means the Mac may sleep.
enum RingIcon {
    static func image(active: Bool, fraction: Double?) -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            let circle = rect.insetBy(dx: 2.5, dy: 2.5)
            let track = NSBezierPath(ovalIn: circle)
            track.lineWidth = 1.6
            NSColor.black.withAlphaComponent(active ? 0.3 : 0.45).setStroke()
            track.stroke()
            guard active else { return true }

            let filled = max(0.02, min(1, fraction ?? 1))
            let arc = NSBezierPath()
            arc.appendArc(
                withCenter: NSPoint(x: rect.midX, y: rect.midY), radius: circle.width / 2,
                startAngle: 90, endAngle: 90 - 360 * filled, clockwise: true
            )
            arc.lineWidth = 2.4
            arc.lineCapStyle = .round
            NSColor.black.setStroke()
            arc.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = active ? "EyesUpGuardian: keeping your Mac awake" : "EyesUpGuardian: your Mac may sleep"
        return image
    }
}
```

- [ ] **Step 3: Write the status item controller**

`Sources/EyesUpApp/MenuBar/StatusItemController.swift`:
```swift
import AppKit
import EyesUpCore
import SwiftUI

/// Owns the menu-bar item. Left-click opens the popover; right-click shows quick actions.
@MainActor
final class StatusItemController: NSObject {
    private let controller: AwakeController
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var minuteTimer: Timer?

    init(controller: AwakeController) {
        self.controller = controller
        super.init()
        popover.behavior = .transient
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: 0, weight: .regular) // 0 = default menu-bar size
        }
        observeController()
        refresh()
    }

    func setPopoverContent<Content: View>(_ view: Content) {
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting
    }

    func refresh() {
        guard let button = statusItem.button else { return }
        let now = Date()
        let until = controller.awakeUntil
        var fraction: Double?
        if let until, let start = controller.sessionStart {
            fraction = TimeFormatting.remainingFraction(now: now, start: start, end: until)
        }
        button.image = RingIcon.image(active: controller.isAwake, fraction: fraction)
        button.title = until.map { " " + TimeFormatting.menuBar(remaining: $0.timeIntervalSince(now)) } ?? ""
        button.toolTip = controller.isAwake
            ? "EyesUpGuardian: " + controller.holds.map(\.label).joined(separator: ", ")
            : "EyesUpGuardian: your Mac may sleep"
        updateMinuteTimer(needed: until != nil)
    }

    // MARK: Observation and timing

    private func observeController() {
        withObservationTracking {
            _ = controller.holds
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.refresh()
                self?.observeController()
            }
        }
    }

    /// The readout changes once a minute, and only while a deadline exists (spec §3: no per-second background work).
    private func updateMinuteTimer(needed: Bool) {
        if needed, minuteTimer == nil {
            let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            timer.tolerance = 5
            RunLoop.main.add(timer, forMode: .common)
            minuteTimer = timer
        } else if !needed {
            minuteTimer?.invalidate()
            minuteTimer = nil
        }
    }

    // MARK: Clicks

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showQuickMenu()
        } else {
            togglePopover(sender)
        }
    }

    private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else if popover.contentViewController != nil {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            NSApp.activate()
            popover.contentViewController?.view.window?.makeKey()
        } else {
            showQuickMenu()
        }
    }

    private func showQuickMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(menuItem("Keep Awake for 1 Hour", #selector(startOneHour)))
        menu.addItem(menuItem("Keep Awake Indefinitely", #selector(startIndefinitely)))
        let stop = menuItem("Stop Keeping Awake", #selector(stopAll))
        stop.isEnabled = controller.isAwake
        menu.addItem(stop)
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit EyesUpGuardian", #selector(quit), key: "q"))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func menuItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func startOneHour() { try? controller.startTimer(duration: 3600, policy: controller.currentPolicy) }
    @objc private func startIndefinitely() { controller.startIndefinite(policy: controller.currentPolicy) }
    @objc private func stopAll() { controller.stopAll() }
    @objc private func quit() { NSApp.terminate(nil) }
}
```

Until Task 11 installs the popover, a left click falls back to the quick menu.

- [ ] **Step 4: Build and run the whole suite**

Run: `make app && swift test`
Expected: `Built build/EyesUpGuardian.app`, and all tests pass (including `sourcesContainNoForbiddenAPIs`, which now scans the app files too).

- [ ] **Step 5: Verify against the real system**

Run: `open build/EyesUpGuardian.app`, then click the menu-bar ring and choose **Keep Awake for 1 Hour**.
Run: `pmset -g assertions | grep EyesUpGuardian`
Expected: a line containing `PreventUserIdleSystemSleep` and `EyesUpGuardian: Timer 1h`. The menu bar shows the ring and `1:00`.

Choose **Stop Keeping Awake**, then run the same `pmset` command.
Expected: no output.

Choose **Keep Awake Indefinitely**, then run `pkill -9 -x EyesUpGuardian; sleep 1; pmset -g assertions | grep EyesUpGuardian`.
Expected: no output. macOS released the assertion when the process died.

Run: `open build/EyesUpGuardian.app; sleep 2; pmset -g assertions | grep EyesUpGuardian`
Expected: `EyesUpGuardian: Indefinitely` is back (restored after the crash).

Choose **Quit EyesUpGuardian**, relaunch, and check `pmset` again.
Expected: no output. A deliberate quit doesn't restore.

- [ ] **Step 6: Commit**

```bash
git add Sources/EyesUpApp
git commit -m "feat(app): add draining-ring menu-bar item with quick menu and wake/clock refresh" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 11: Ambient quick popover

**Files:**
- Create: `Sources/EyesUpApp/Popover/AmbientBackground.swift`, `Sources/EyesUpApp/Popover/PopoverView.swift`
- Modify: `Sources/EyesUpApp/EyesUpGuardianApp.swift` (install the popover content)

**Interfaces:**
- Consumes:
  - from `AwakeController`: `holds`, `isAwake`, `awakeUntil`, `displayOn`, `lastError`, `storeNotice`, `currentPolicy`, `startTimer`, `startIndefinite`, `startUntil`, `watchProcess`, `parsePID`, `extend`, `setDisplayOn`, `stop`, `stopAll`, `nudgeDisplay`;
  - `DurationParser`, `TimeFormatting`, `Defaults`;
  - `StatusItemController.setPopoverContent(_:)`.
- Produces: `PopoverView(controller:)` and `AmbientBackground(mood:)`. Plan 3 reuses `AmbientBackground` in the dashboard and HUD.

- [ ] **Step 1: Write the ambient background**

`Sources/EyesUpApp/Popover/AmbientBackground.swift`:
```swift
import AppKit
import SwiftUI

/// Ambient style: a soft glow whose color follows state. It animates only when the mood changes, never on a loop.
struct AmbientBackground: View {
    enum Mood: Equatable { case idle, awake }

    let mood: Mood
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            if reduceTransparency { Color(nsColor: .windowBackgroundColor) }
            RadialGradient(colors: [primary.opacity(0.55), .clear], center: .topLeading, startRadius: 0, endRadius: 300)
            RadialGradient(colors: [secondary.opacity(0.4), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 300)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: mood)
        .allowsHitTesting(false)
    }

    var primary: Color {
        mood == .awake ? Color(red: 1.0, green: 0.63, blue: 0.35) : Color(red: 0.45, green: 0.40, blue: 0.75)
    }

    private var secondary: Color {
        mood == .awake ? Color(red: 0.55, green: 0.35, blue: 1.0) : Color(red: 0.25, green: 0.25, blue: 0.45)
    }
}
```

- [ ] **Step 2: Write the popover**

`Sources/EyesUpApp/Popover/PopoverView.swift`:
```swift
import AppKit
import EyesUpCore
import SwiftUI

struct PopoverView: View {
    let controller: AwakeController

    private enum Entry { case none, until, custom, pid }

    @State private var entry: Entry = .none
    @State private var untilDate = Date().addingTimeInterval(3600)
    @State private var customText = ""
    @State private var pidText = ""
    @State private var errorMessage: String?
    @State private var displayForNew = false

    private var mood: AmbientBackground.Mood { controller.isAwake ? .awake : .idle }
    private var newPolicy: SleepPolicy { displayForNew || controller.displayOn ? [.system, .display] : .system }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            presets
            entryPanel
            if controller.isAwake { activeHolds }
            messages
            footer
        }
        .padding(18)
        .frame(width: 320)
        .background(AmbientBackground(mood: mood))
    }

    // MARK: Header: live countdown (TimelineView ticks only while the popover is on screen)

    private var header: some View {
        HStack(alignment: .top) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline).font(.callout).foregroundStyle(.secondary)
                    Text(bigText(now: context.date))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .shadow(color: AmbientBackground(mood: mood).primary.opacity(0.6), radius: 12)
                    if controller.isAwake {
                        Text(controller.holds.map(\.label).joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }
            Spacer()
            Toggle("Keep awake", isOn: Binding(
                get: { controller.isAwake },
                set: { on in
                    if on { controller.startIndefinite(policy: newPolicy) } else { controller.stopAll() }
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .tint(.orange)
        }
    }

    private var headline: String {
        guard controller.isAwake else { return "Your Mac may sleep" }
        return controller.awakeUntil == nil ? "Awake" : "Awake for another"
    }

    private func bigText(now: Date) -> String {
        guard controller.isAwake else { return "Idle" }
        guard let until = controller.awakeUntil else { return "No end time" }
        return TimeFormatting.countdown(until.timeIntervalSince(now))
    }

    // MARK: Presets and entry

    private var presets: some View {
        VStack(alignment: .leading, spacing: 8) {
            GlassEffectContainer {
                HStack(spacing: 6) {
                    ForEach(Defaults.presets, id: \.self) { seconds in
                        Button(TimeFormatting.duration(seconds)) {
                            run { try controller.startTimer(duration: seconds, policy: newPolicy) }
                        }
                        .buttonStyle(.glass)
                    }
                    Button("∞") { run { controller.startIndefinite(policy: newPolicy) } }
                        .buttonStyle(.glass)
                        .accessibilityLabel("Keep awake indefinitely")
                }
            }
            HStack(spacing: 6) {
                entryButton("Until…", .until)
                entryButton("Custom…", .custom)
                entryButton("Process…", .pid)
                Spacer()
                Toggle("Display on", isOn: Binding(
                    get: { controller.isAwake ? controller.displayOn : displayForNew },
                    set: { on in
                        displayForNew = on
                        if controller.isAwake { controller.setDisplayOn(on) }
                    }
                ))
                .toggleStyle(.button)
                .help("Keep the display on too (caffeinate -d)")
            }
            .controlSize(.small)
        }
    }

    private func entryButton(_ title: String, _ target: Entry) -> some View {
        Button(title) {
            entry = entry == target ? .none : target
            errorMessage = nil
        }
        .buttonStyle(.glass)
    }

    @ViewBuilder
    private var entryPanel: some View {
        switch entry {
        case .none:
            EmptyView()
        case .until:
            HStack {
                DatePicker("Until", selection: $untilDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                Button("Start") { run { try controller.startUntil(untilDate, policy: newPolicy) } }
                    .buttonStyle(.glassProminent).tint(.orange)
            }
        case .custom:
            HStack {
                TextField("45m, 2h or 1h30m", text: $customText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(startCustom)
                Button("Start", action: startCustom).buttonStyle(.glassProminent).tint(.orange)
            }
        case .pid:
            HStack {
                TextField("Process ID, e.g. 48213", text: $pidText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(startPID)
                Button("Watch", action: startPID).buttonStyle(.glassProminent).tint(.orange)
            }
        }
    }

    private func startCustom() {
        run {
            switch DurationParser.parse(customText) {
            case .finite(let seconds): try controller.startTimer(duration: seconds, policy: newPolicy)
            case .infinite: controller.startIndefinite(policy: newPolicy)
            case nil: throw AwakeError.invalidDuration
            }
            customText = ""
        }
    }

    private func startPID() {
        run {
            try controller.watchProcess(pid: AwakeController.parsePID(pidText), policy: newPolicy)
            pidText = ""
        }
    }

    // MARK: Active holds

    private var activeHolds: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(controller.holds) { hold in
                HStack {
                    Image(systemName: icon(for: hold)).foregroundStyle(.orange)
                    Text(hold.label).lineLimit(1)
                    Spacer()
                    Button {
                        controller.stop(id: hold.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Stop \(hold.label)")
                }
                .font(.callout)
            }
            HStack(spacing: 6) {
                if controller.awakeUntil != nil {
                    Button("+30m") { run { try controller.extend(by: Defaults.extendStep, policy: controller.currentPolicy) } }
                        .buttonStyle(.glass)
                }
                Button {
                    controller.nudgeDisplay()
                } label: {
                    Label("Wake display", systemImage: "sun.max")
                }
                .buttonStyle(.glass)
                .help("Wake the display now (caffeinate -u)")
                Spacer()
                Button("Stop all") { controller.stopAll() }
                    .buttonStyle(.glass)
            }
            .controlSize(.small)
        }
    }

    private func icon(for hold: Hold) -> String {
        switch hold.end {
        case .indefinite: "infinity"
        case .deadline: "timer"
        case .processExit: "gearshape"
        case .triggerControlled: "bolt"
        }
    }

    // MARK: Messages and footer

    @ViewBuilder
    private var messages: some View {
        if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
        }
        if let error = controller.lastError {
            Label("macOS refused a keep-awake request (code \(error.code)). Retrying on the next change.",
                  systemImage: "exclamationmark.octagon")
                .font(.caption).foregroundStyle(.red)
        }
        if let notice = controller.storeNotice {
            Label(notice, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            Text("EyesUpGuardian").font(.caption2).foregroundStyle(.tertiary)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func run(_ action: () throws -> Void) {
        do {
            try action()
            errorMessage = nil
            entry = .none
        } catch let error as AwakeError {
            errorMessage = error.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

- [ ] **Step 3: Install the popover**

In `Sources/EyesUpApp/EyesUpGuardianApp.swift`, replace:
```swift
        statusItem = StatusItemController(controller: environment.controller)
```
with:
```swift
        let statusItem = StatusItemController(controller: environment.controller)
        statusItem.setPopoverContent(PopoverView(controller: environment.controller))
        self.statusItem = statusItem
```

- [ ] **Step 4: Build and run the suite**

Run: `make app && swift test`
Expected: the build succeeds and all tests pass.

- [ ] **Step 5: Verify manually**

Run: `open build/EyesUpGuardian.app` and left-click the ring. Check each item:

| Action | Expected result |
|---|---|
| Open the popover while idle | Violet glow, "Your Mac may sleep", "Idle" |
| Click **2h** | Glow turns warm amber, countdown `1:59:59` ticks, reasons line shows "Timer 2h", menu bar shows `2:00` |
| Click **Display on**, then run `pmset -g assertions \| grep EyesUpGuardian` | Both `PreventUserIdleDisplaySleep` and `PreventUserIdleSystemSleep` listed |
| **Custom…**: type `abc`, press Return | Orange error "Choose a duration between 1 minute and 999 hours." and no new hold |
| **Custom…**: type `1h30m`, press Return | Timer replaced with "Timer 1h 30m" |
| **Process…**: type `0` | "Enter a process ID using digits only, like 48213." |
| Run `sleep 120 &` in Terminal, then **Process…** with that PID | Hold "PID <n> · sleep" appears; when `sleep` ends, the hold disappears within a second |
| **Until…**: pick a time 2 minutes ahead, then **Start** | Countdown to that time |
| Click **+30m** | Deadline moves 30 minutes later; label shows "Until …" |
| Click **Stop all** | Glow returns to violet, and `pmset` output is empty |
| System Settings → Accessibility → Display → Reduce motion on, then start a timer | The glow switches without animating |
| Close the popover, then check Activity Monitor | EyesUpGuardian CPU drops to 0.0% (the countdown only runs while the popover is open) |

- [ ] **Step 6: Commit**

```bash
git add Sources/EyesUpApp
git commit -m "feat(app): add Ambient quick popover with presets, custom, until, process watching and holds list" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 12: Heads-up notification with +30m / +1h / ∞ actions

**Files:**
- Create: `Sources/EyesUpApp/Notifications/HeadsUpNotifier.swift`
- Modify: `Sources/EyesUpApp/EyesUpGuardianApp.swift` (create the notifier)

**Interfaces:**
- Consumes: `AwakeController.setHeadsUpHandler(_:)`, `extend(by:policy:)`, `startIndefinite(policy:)`, `currentPolicy`.
- Produces: `HeadsUpNotifier(controller:)`.

- [ ] **Step 1: Write the notifier**

`Sources/EyesUpApp/Notifications/HeadsUpNotifier.swift`:
```swift
import EyesUpCore
import Foundation
import UserNotifications

/// Posts "Keep-awake ends at 11:24 PM" before the Mac may sleep, with one-tap extensions.
@MainActor
final class HeadsUpNotifier: NSObject, UNUserNotificationCenterDelegate {
    private static let categoryID = "EYESUP_HEADS_UP"

    private enum Action: String {
        case extend30 = "EXTEND_30M"
        case extend60 = "EXTEND_1H"
        case indefinite = "INDEFINITE"
    }

    private let controller: AwakeController
    /// nil when running unbundled (for example `swift run`), where UserNotifications is unavailable.
    private let center: UNUserNotificationCenter?

    init(controller: AwakeController) {
        self.controller = controller
        center = Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
        super.init()
        guard let center else { return }

        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.categoryID,
                actions: [
                    UNNotificationAction(identifier: Action.extend30.rawValue, title: "+30 min"),
                    UNNotificationAction(identifier: Action.extend60.rawValue, title: "+1 hour"),
                    UNNotificationAction(identifier: Action.indefinite.rawValue, title: "Keep awake ∞"),
                ],
                intentIdentifiers: []
            ),
        ])
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        controller.setHeadsUpHandler { [weak self] end in self?.post(end: end) }
    }

    private func post(end: Date) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = "EyesUpGuardian"
        content.body = "Keep-awake ends at \(end.formatted(date: .omitted, time: .shortened)). Your Mac may sleep after that."
        content.categoryIdentifier = Self.categoryID
        center.add(UNNotificationRequest(identifier: "heads-up", content: content, trigger: nil)) { _ in }
    }

    private func handle(actionID: String) {
        switch Action(rawValue: actionID) {
        case .extend30: try? controller.extend(by: 1800, policy: controller.currentPolicy)
        case .extend60: try? controller.extend(by: 3600, policy: controller.currentPolicy)
        case .indefinite: controller.startIndefinite(policy: controller.currentPolicy)
        case nil: break
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let actionID = response.actionIdentifier
        await MainActor.run { handle(actionID: actionID) }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
```

- [ ] **Step 2: Create it at launch**

In `Sources/EyesUpApp/EyesUpGuardianApp.swift`, add a stored property to `AppDelegate`:
```swift
    private var headsUp: HeadsUpNotifier?
```
and, in `applicationDidFinishLaunching`, directly after `environment.start()`:
```swift
        headsUp = HeadsUpNotifier(controller: environment.controller)
```

- [ ] **Step 3: Build and run the suite**

Run: `make app && swift test`
Expected: the build succeeds and all tests pass.

- [ ] **Step 4: Verify manually**

1. Run `open build/EyesUpGuardian.app`. The first launch asks for notification permission; click **Allow**.
2. **Custom…** → `6m`.
3. About 1 minute later, a banner appears: "Keep-awake ends at …". Hover it and choose **+30 min**.

Expected: the popover countdown jumps by 30 minutes, and the label changes to "Until …".

4. Quit, then relaunch the app. Start **Custom…** → `6m`, and choose **Keep awake ∞** on the banner.

Expected: the reasons line shows "Indefinitely", and the menu bar shows a full ring with no time.

- [ ] **Step 5: Commit**

```bash
git add Sources/EyesUpApp
git commit -m "feat(app): add heads-up notification with extend and indefinite actions" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 13: Performance gate, manual checklist, README, and final verification

**Files:**
- Create: `Scripts/perf.sh`, `docs/manual-test-checklist.md`, `README.md`
- Modify: `Makefile` (add a `perf` target)

**Interfaces:**
- Consumes: `build/EyesUpGuardian.app`.
- Produces:
  - `make perf`, which exits non-zero when idle CPU ≥ 0.1% or footprint > 30 MB;
  - the checklist and README later plans extend.

- [ ] **Step 1: Write the perf script**

`Scripts/perf.sh` (then `chmod +x Scripts/perf.sh`):
```bash
#!/bin/bash
# Spec §3 idle budget: < 0.1% CPU over 60 s and <= 30 MB memory footprint (Activity Monitor's "Memory").
# Note: quits any running EyesUpGuardian first.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/EyesUpGuardian.app"
MAX_CPU_PERCENT="0.1"
MAX_FOOTPRINT_MB="30"
SETTLE_SECONDS="${SETTLE_SECONDS:-30}"
SAMPLE_SECONDS="${SAMPLE_SECONDS:-60}"

pkill -x EyesUpGuardian 2>/dev/null || true
sleep 1
open -n "$APP"
sleep 3
PID="$(pgrep -nx EyesUpGuardian)"
trap 'kill "$PID" 2>/dev/null || true' EXIT
echo "EyesUpGuardian PID $PID. Settling for ${SETTLE_SECONDS}s..."
sleep "$SETTLE_SECONDS"

# ps prints cumulative CPU time as m:ss.cc (or h:mm:ss.cc).
cpu_seconds() {
    ps -o time= -p "$PID" | awk '{ n = split($1, p, ":"); t = 0; for (i = 1; i <= n; i++) t = t * 60 + p[i]; print t }'
}

START="$(cpu_seconds)"
sleep "$SAMPLE_SECONDS"
END="$(cpu_seconds)"
FOOTPRINT_MB="$(footprint -p "$PID" | awk '/phys_footprint:/ { v = $2; u = $3; if (u == "KB") v /= 1024; else if (u == "GB") v *= 1024; printf "%.1f", v; exit }')"
CPU_PERCENT="$(awk -v s="$START" -v e="$END" -v t="$SAMPLE_SECONDS" 'BEGIN { printf "%.3f", (e - s) / t * 100 }')"

echo "Idle CPU:  ${CPU_PERCENT}% (limit < ${MAX_CPU_PERCENT}%)"
echo "Footprint: ${FOOTPRINT_MB} MB (limit <= ${MAX_FOOTPRINT_MB} MB)"
if awk -v c="$CPU_PERCENT" -v m="$FOOTPRINT_MB" -v mc="$MAX_CPU_PERCENT" -v mm="$MAX_FOOTPRINT_MB" 'BEGIN { exit !(c < mc && m <= mm) }'; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi
```

Add to `Makefile` (recipe lines start with a tab), and change the first line to `.PHONY: app test test-integration perf install run clean`:
```make
perf: app
	Scripts/perf.sh
```

- [ ] **Step 2: Run the perf gate**

Run: `make perf`
Expected: the footprint and CPU lines are printed, then `PASS`. It takes about 95 s.
If it FAILS: do not raise the limits. Use superpowers:systematic-debugging to find the idle work (for example a timer firing while nothing is visible) and fix it.

- [ ] **Step 3: Write the manual checklist**

`docs/manual-test-checklist.md`:
```markdown
# Manual test checklist

Run before every release. Each check needs a fresh `make app` build.

## Menu bar
- [ ] Idle: faint ring, no time shown.
- [ ] Timer running: ring drains over time; readout `h:mm`, or `Nm` under an hour; it updates each minute.
- [ ] Indefinite: full ring, no time.
- [ ] Right-click menu: 1 hour / Indefinitely / Stop (disabled when idle) / Quit.

## Popover
- [ ] Presets 15m, 1h, 2h, 4h and ∞ each replace the current manual session.
- [ ] Until… rejects past times; Custom… rejects `abc`, `0m`, `1000h`; Process… rejects `0`, `abc`, and its own PID.
- [ ] Watching a process that exits removes its hold within a second.
- [ ] Display on adds `PreventUserIdleDisplaySleep` (check with `pmset -g assertions`).
- [ ] Wake display wakes a sleeping display.
- [ ] +30m extends; Stop all releases everything.

## Safety and restore
- [ ] `pkill -9 -x EyesUpGuardian` → `pmset -g assertions` shows nothing from EyesUpGuardian.
- [ ] Relaunch after the kill → holds restored.
- [ ] Deliberate Quit → relaunch → no holds.
- [ ] Put the Mac to sleep past a timer's end (Apple menu → Sleep); on wake the hold is already gone.
- [ ] Write garbage into `~/Library/Application Support/EyesUpGuardian/holds.json` → launch → clean start with the "couldn't be read" notice.

## Notifications
- [ ] Heads-up 5 minutes before the end; +30 min, +1 hour and ∞ all work.

## Accessibility
- [ ] Reduce motion: no glow animation.
- [ ] Reduce transparency: solid popover background.
- [ ] VoiceOver reads the ring state, the countdown, and every button.

## Performance
- [ ] `make perf` passes.
- [ ] Popover open: CPU under 1.5% in Activity Monitor (spec §3 dashboard-open target).
```

- [ ] **Step 4: Write the README**

`README.md`:
````markdown
# EyesUpGuardian

A native macOS menu-bar app that keeps your Mac awake. It's a safe, clickable replacement for `caffeinate` and Amphetamine.

- Timers, indefinite, until a time, or until a process exits (kernel-notified, PID-reuse safe)
- Every `caffeinate` sleep type: system (`-i`), display (`-d`), disk (`-m`), system on AC (`-s`), user-activity nudge (`-u`)
- A draining-ring menu-bar icon, an Ambient popover, and a heads-up notification before your Mac may sleep
- If the app crashes, macOS releases the hold automatically, so your Mac is never stuck awake

## Safety

EyesUpGuardian never runs shell commands, never asks for admin rights, never touches the network, and has zero third-party dependencies. It talks to macOS power management directly (the same IOKit interface `caffeinate` uses). A test fails the build if forbidden APIs ever appear in the source. You can inspect what it's doing at any time:

```bash
pmset -g assertions | grep EyesUpGuardian
```

## Build

Requires macOS 26 and the Xcode Command Line Tools (`xcode-select --install`). Full Xcode is not needed.

```bash
make app       # builds build/EyesUpGuardian.app
make install   # copies it to /Applications
make test      # unit tests
```

The app is ad-hoc signed. On first launch of a downloaded build, right-click the app → Open.

## License

MIT
````

- [ ] **Step 5: Final verification**

Run: `swift test && make test-integration && make perf`
Expected: all unit tests pass; the integration suite passes; perf prints `PASS`.
Then work through `docs/manual-test-checklist.md` and tick every box that applies to Plan 1. Plan 1 has no dashboard, so skip anything not built yet.

- [ ] **Step 6: Commit**

```bash
git add Scripts/perf.sh Makefile docs/manual-test-checklist.md README.md
git commit -m "chore: add idle performance gate, manual checklist and README" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```
