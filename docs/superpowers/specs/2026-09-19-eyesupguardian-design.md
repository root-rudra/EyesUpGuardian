# EyesUpGuardian: Design Spec

- **Date:** 2026-09-19
- **Status:** Approved in brainstorming; awaiting written-spec review
- **Platform:** macOS 26+ (Apple Silicon first; built and tested on a Mac Studio M3 Ultra)

## 1. Purpose and success criteria

EyesUpGuardian is a native macOS menu-bar app that keeps the Mac awake. It replaces Amphetamine and the `caffeinate` command, and adds a live system dashboard. Its main job is to keep the owner's Mac Studio awake during long, unattended work, such as AI-assisted app development sessions, builds and downloads. It must be good enough to publish as an open-source GitHub project.

The app succeeds when:

1. Every `caffeinate` capability is available from a clickable UI. It also offers automatic triggers that `caffeinate` lacks (app running, process running, schedule, activity-based).
2. It never executes shell commands, never needs admin rights, and never touches the network.
3. At idle it uses **< 0.1% CPU (averaged over 60 s) and ≤ 30 MB resident memory**, verified by `make perf`.
4. A crash can never leave the Mac stuck awake, and valid keep-awake sessions survive a relaunch.
5. It shows useful live system stats (CPU, memory, power, temperatures, processes, and more) without admin rights.
6. A stranger can clone the repo, run one command, and get a working app.

### Decisions made during brainstorming

| Topic | Decision |
|---|---|
| Keep-awake modes | All of them are first-class: manual timer, indefinite, until-PID-exits, while-app-runs, schedules, activity triggers |
| macOS target | macOS 26+ only (Liquid Glass, newest SwiftUI) |
| App shape | Menu-bar item with live readout + quick popover + full dashboard window + pinnable floating HUD |
| Visual style | "Ambient" for everything except the Processes tab, which uses "Mission Control" (dense, monospaced) |
| Tech stack | Native Swift 6 + SwiftUI, Swift Package Manager + Makefile, **no Xcode required** |
| Signing | Build-from-source now; release pipeline designed so notarization drops in once an Apple Developer account exists |
| Stats | All of those listed in §6 |
| Process control | Quit / Force Quit only for the current user's processes, always with a confirmation dialog |
| Resource budget | Super lightweight, maximum stability (hard requirement, §3) |

## 2. Architecture

One process, one Swift package, zero third-party dependencies.

```
EyesUpGuardian/
├── Package.swift
├── Makefile                  # app, test, perf, install, clean
├── Sources/
│   ├── EyesUpCore/           # library: all logic, no UI imports
│   │   ├── Holds/            # Hold model, HoldRegistry
│   │   ├── Engine/           # AwakeEngine + PowerAssertionProviding protocol
│   │   ├── Triggers/         # one file per trigger type
│   │   ├── Metrics/          # Sampler + one probe per stat
│   │   │   └── Private/      # probes using undocumented interfaces (isolated)
│   │   ├── Processes/        # process list, PID identity, quit
│   │   ├── Automation/       # URL-scheme parser/validator
│   │   └── Store/            # settings, saved triggers, history (JSON)
│   └── EyesUpApp/            # SwiftUI executable: UI only
│       ├── MenuBar/  Popover/  Dashboard/  HUD/  Notifications/  Settings/
│       └── Resources/        # Info.plist, asset catalog, app icon
├── Tests/EyesUpCoreTests/
├── Scripts/                  # bundle.sh (assemble .app, ad-hoc sign), perf.sh
└── docs/
```

- **EyesUpCore** holds all logic and imports no SwiftUI or AppKit UI. Every macOS dependency sits behind a small protocol (`PowerAssertionProviding`, `ProcessInspecting`, `Clock`, `WorkspaceEvents`), so tests can inject fakes.
- **EyesUpApp** renders state and forwards user intents ("start 2h timer", "watch PID 48213") to the core. It never calls power management directly.
- **Data flow:** intents go down; `@Observable` state (holds, engine status, metrics) comes up. Mutable core state lives on the main actor. The sampler does its work on one background serial queue and publishes results to the main actor. Swift 6 strict concurrency is enabled.

## 3. Resource and stability requirements (hard constraints)

1. **Sample on demand.** Nothing is sampled unless a visible UI element or an enabled trigger subscribes to it (§6).
2. **No idle animation.** Ambient glow changes are driven by state transitions only. When state is steady, no animation runs.
3. **No per-second background tick.** Timers wake only at their deadlines. Live countdowns are drawn only while a window is visible (SwiftUI `TimelineView`).
4. **Bounded memory.** Chart histories are fixed-size ring buffers (300 samples per stat). History on disk is capped (§8).
5. **Single process.** No helpers, daemons, XPC services or child processes.
6. **Targets:** idle CPU < 0.1% (60 s average), idle RSS ≤ 30 MB, and dashboard-open CPU < 1.5%. `make perf` enforces the idle targets. The dashboard-open target is checked in the manual checklist.
7. **Crash safety.** Power assertions belong to the process, so the kernel releases them if the app dies. Persisted holds are restored on launch (§4.4).
8. **Graceful degradation.** Any probe that fails or is unavailable reports `.unavailable`. The UI hides that stat with a "Not available on this Mac" note, and nothing crashes.

## 4. Awake engine

### 4.1 Holds

A **Hold** is one reason to stay awake:

```swift
struct Hold: Identifiable, Codable {
    let id: UUID
    var source: HoldSource        // .manual, .trigger(TriggerID), .automation
    var label: String             // "Timer 2h", "Claude running", "PID 48213 swift-build"
    var policy: SleepPolicy       // OptionSet: .system, .display, .disk, .systemOnAC
    var end: HoldEnd              // .indefinite, .deadline(Date), .processExit(ProcessIdentity), .triggerControlled
    var grace: Duration?          // keep holding this long after the end condition
    var createdAt: Date
}
```

`HoldRegistry` owns the active holds. It is the only place holds are added or removed.

### 4.2 Engine reconciliation

`AwakeEngine` observes the registry. On every change, it computes the union of the active holds' policies and diffs it against the assertions it currently holds. Then it creates or releases the minimum set of IOKit assertions:

| Policy flag | `caffeinate` flag | IOKit assertion |
|---|---|---|
| `.display` | `-d` | `kIOPMAssertionTypePreventUserIdleDisplaySleep` |
| `.system` | `-i` | `kIOPMAssertionTypePreventUserIdleSystemSleep` |
| `.systemOnAC` | `-s` | `kIOPMAssertionTypePreventSystemSleep` |
| `.disk` | `-m` | `kIOPMAssertionTypePreventDiskIdle` (in advanced settings) |
| "Nudge display" action | `-u` | `IOPMAssertionDeclareUserActivity` (one-shot action, not a hold) |
| Timer | `-t` | `HoldEnd.deadline` |
| Until PID exits | `-w` | `HoldEnd.processExit` |

- There is **at most one assertion per type**. Its name is updated to list the active reasons, for example `EyesUpGuardian: Timer 2h · Claude running`. This makes `pmset -g assertions` a readable audit trail.
- **`caffeinate <utility>` (run a command) is intentionally not supported.** The user starts the command, then picks "watch this process".
- **Default policy for new holds:** `.system` (display may sleep). The user can change this default in Settings, and each hold has a "Display on" toggle.

### 4.3 Hold end handling

- **Deadlines** are absolute `Date`s, which makes them correct across clock changes and sleep. One `DispatchSourceTimer` is armed for the earliest deadline (including grace) and re-armed on every change. A second deadline is armed at `earliest − headsUpLead` (default 5 min) to post the heads-up notification (§7.5).
- **Process exit:** the engine uses `DispatchSource.makeProcessSource(identifier:eventMask:.exit)` (kqueue `NOTE_EXIT`).
  - **PID-reuse protection:** `ProcessIdentity = (pid, startTime)`, where `startTime` comes from `proc_pidinfo(PROC_PIDTBSDINFO).pbi_start_tvsec/usec`.
  - A hold is created only if the PID currently exists and its identity is captured at that moment.
  - On restore and before any action, the identity is re-verified. A mismatch means the original process is gone.

### 4.4 Persistence and restore

Active holds are written to `holds.json` on every change, and restored on launch as follows:

| Hold kind | Restore rule |
|---|---|
| Deadline hold | Restored only if its deadline is in the future |
| Process hold | Restored only if `ProcessIdentity` still matches |
| Indefinite manual hold | Restored |
| Trigger-controlled hold | Not persisted; the trigger re-evaluates on launch |

### 4.5 Safety guards (Settings, both opt-in)

- **Thermal auto-release:** release all holds when `ProcessInfo.thermalState == .critical`, and notify the user.
- **Safety cap:** no hold may exceed N hours (user-set). Such holds are released with a notification.
- **Pause all triggers** for 1 h / 4 h / until resumed. Manual holds are unaffected.

## 5. Triggers

A **Trigger** is a saved rule. It has:
- a condition;
- a `SleepPolicy`;
- an optional grace period;
- `notifyOnChange: Bool`;
- `isEnabled: Bool`.

While its condition is true, the trigger owns exactly one hold, with `end = .triggerControlled`. When the condition becomes false, the hold is released after the grace period. Triggers are persisted in `triggers.json`.

| Trigger | Condition | Detection | Background cost |
|---|---|---|---|
| App running | Any of the chosen bundle IDs is running | `NSWorkspace` `didLaunch`/`didTerminate` notifications, plus an initial `runningApplications` scan. Matched by **bundle ID**, not name. | Event-driven, none |
| Process running | A process with the chosen executable name(s) is running (for CLI tools: `claude`, `node`, `swift-build`) | `proc_listallpids` + name lookup every 10 s **only while enabled**. On a match, it switches to kqueue exit watching for that process. | Tiny |
| Specific PID | Chosen via a manual hold; see §4.3 | kqueue | None |
| Schedule | Weekday set + start/end time (may cross midnight) | One timer for the next boundary; re-evaluates on wake and on clock/timezone change notifications | None |
| CPU busy | Total CPU > X% sustained for M min | Samples every 15 s; **hysteresis**: releases only after below X for 5 min (configurable) | Tiny |
| Network busy | Throughput > X MB/s sustained for M min | `getifaddrs` byte counters every 15 s, with hysteresis | Tiny |
| Disk busy | Disk write > X MB/s sustained for M min | IOBlockStorageDriver statistics every 15 s, with hysteresis | Tiny |
| Display connected | A chosen external display (by vendor/model/serial) is connected | `CGDisplayRegisterReconfigurationCallback` | None |
| On AC power | Power source is AC (useful for laptop users) | `IOPSNotificationCreateRunLoopSource` | None |

**Suggestions:** when the Triggers tab is open, it checks running apps against a small built-in list (Claude, Terminal, iTerm, Xcode, VS Code, Docker) and against apps the user has held for before. Matches are offered as one-click "Keep awake while X runs?" cards. This check runs only while the tab is visible.

### 5.1 Automation URL scheme (off by default)

- **Scheme:** `eyesup://`.
- **Accepted commands:**
  - `start?for=<duration>&display=<bool>`, where `<duration>` is like `90m`, `2h` or `1h30m`, or `inf`;
  - `stop`;
  - `extend?by=<duration>`.
- **Validation:** strict. Unknown commands or parameters are rejected. Durations must match `^(\d{1,3}h)?(\d{1,4}m)?$` or equal `inf`, and are capped at 24 h, or at the safety cap if one is set and lower.
- **It can never** quit processes, change settings or create triggers.
- **Visibility:** each accepted command posts a notification and is recorded in history with source `.automation`. It is enabled only through a Settings toggle.

## 6. Metrics

### 6.1 Sampler

- Each stat is a `Probe` with an identifier, a minimum interval and a `sample() -> ProbeResult`.
- UI components and triggers **subscribe** to probe IDs with a desired interval. The sampler runs the subscribed probes at the fastest requested interval on one background serial queue, and publishes to the main actor.
- **Zero subscribers means the sampler timer is cancelled.**
- Rate probes (CPU, network, disk) keep their previous raw counters to compute deltas.
- Visibility rules:

| Visible UI | Subscriptions |
|---|---|
| Nothing (steady state) | Only the stats in the chosen menu-bar readout, at 2 s. Nothing at all if the readout is the icon or timer only. Energy tally at 30 s if enabled. Plus trigger probes. |
| Popover or HUD | Its 4 headline stats (HUD: 5) at 1 s |
| Dashboard | Only the **visible tab's** probes: 1 s for charts, 2 s for processes. Unsubscribes when the window is hidden, minimized or fully occluded (`NSWindow.occlusionState`). |

### 6.2 Probes

**Documented APIs:**

| Stat | Source |
|---|---|
| CPU total + per core | `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` |
| P-cluster vs E-cluster load | Per-core load grouped by `hw.perflevel0/1.logicalcpu` sysctls |
| Memory used/app/wired/compressed | `host_statistics64(HOST_VM_INFO64)` |
| Memory pressure | `kern.memorystatus_vm_pressure_level` sysctl |
| Swap | `vm.swapusage` sysctl |
| Uptime | `kern.boottime` sysctl |
| Load average | `getloadavg` |
| Thermal state | `ProcessInfo.thermalState` |
| Idle time | `HIDIdleTime` from the `IOHIDSystem` registry entry |
| Disk free | `URLResourceValues.volumeAvailableCapacityForImportantUsage` |
| Disk read/write rate | `IOBlockStorageDriver` "Statistics" registry property |
| Network up/down rate | `getifaddrs` `if_data` counters (non-loopback) |
| Processes | `proc_listallpids`, `proc_pidinfo`, `proc_pid_rusage` (CPU-time deltas, `ri_phys_footprint`), `proc_pidpath`. Processes the user cannot inspect show "—". |
| Process/thread counts | Derived from the process scan |
| Other apps' sleep assertions | `IOPMCopyAssertionsByProcess` (our own entries filtered out) |
| Sleep/wake log | `IORegisterForSystemPower` sleep/wake notifications recorded while the app runs. Wake reason read from the `IOPMrootDomain` registry properties when present. |
| GPU utilization | `IOAccelerator` "PerformanceStatistics" → "Device Utilization %" registry property (a registry read, not a private API) |

**Undocumented interfaces** (isolated in `Metrics/Private/`, each gated by an availability check):

| Stat | Source |
|---|---|
| System total watts | SMC key `PSTR` via the `AppleSMC` user client |
| CPU / GPU / ANE watts, cluster frequencies | IOReport "Energy Model" and "CPU Stats" channels (`libIOReport.dylib`, loaded with `dlopen`/`dlsym` so a missing symbol means `.unavailable`, not a launch failure) |
| Temperatures | IOHID temperature sensor services, falling back to SMC temperature keys |
| Fan RPM | SMC `F0Ac`, `F1Ac`, … |

**Feasibility gate:** implementation task 1 is a throwaway spike that prints each private probe's output on the target Mac Studio. Probes that fail there ship disabled (hidden) and are listed in the README as "not available".

### 6.3 Energy cost

- **Calculation:** integrates system watts over time into daily kWh buckets, and multiplies by the user-set electricity rate ($/kWh, default unset, which hides the dollar figure).
- **Availability:** only when system watts is available.
- **Sampling:** every 30 s while the setting "Track energy" is on (default on if watts is available).

## 7. UI

All surfaces use the **Ambient** style except the Processes tab (**Mission Control**). They use real macOS 26 Liquid Glass materials, SF Symbols and SF Pro, SF Mono for Mission Control. They honor Reduce Motion (no glow transitions, no number rolling) and Reduce Transparency (solid backgrounds). Every control is keyboard-reachable and VoiceOver-labeled.

**Ambient style:** a background glow color driven by state:

| State | Glow |
|---|---|
| Idle | Cool, dim violet |
| Awake | Warm amber |
| Heavy load (CPU > 80% or thermal ≥ serious) | Red-shifted amber |
| Paused | Grey |

Transitions animate over 0.6 s only when the state changes.

### 7.1 Menu-bar item

- **Icon:** a ring glyph that drains as the earliest deadline approaches. It shows a full ring for indefinite or trigger holds, and a dimmed empty ring when idle.
- **Readout variants** (Settings):
  1. icon only;
  2. icon + time left;
  3. icon + time left + user-chosen stats (CPU %, RAM, watts, temperature, network).
- **Clicks:** left click opens the popover. Right click shows a small menu: Start default, Stop, Open Dashboard, Pin HUD, Quit.

### 7.2 Quick popover

- **Header:** "Awake for another 1h 42m" (or "Awake: no end time" / "Mac may sleep"), with the reasons listed below it.
- **Controls:**
  - preset chips (15m, 1h, 2h, 4h, ∞, Until…; editable in Settings);
  - a "Display on" toggle, "+30m" and "Stop";
  - a master switch.
- **Stats and warnings:**
  - four stat tiles: CPU, RAM, Power, Uptime (Power swaps to Temperature if watts is unavailable);
  - a warning row when other apps hold sleep assertions ("Zoom is also preventing display sleep").
- **Footer:** Pin HUD, Open Dashboard.

### 7.3 Dashboard window

A sidebar with five tabs (⌘1–⌘5):

1. **Overview (Ambient):**
   - a large glowing countdown and the active reasons;
   - gauges for CPU, RAM and Power;
   - secondary tiles for GPU, temperature, fan, P/E cluster load, uptime, idle time, network, disk and swap;
   - the "Other apps keeping the Mac awake" list.
2. **Triggers:** suggestion cards; one card per trigger with an enable switch, summary, edit sheet and delete; "+ New trigger"; "Pause all".
3. **Processes (Mission Control):**
   - header: process count, thread count, load averages;
   - a sortable, filterable table: Name, PID, CPU %, Memory, Threads, User;
   - row actions: *Keep awake until this exits* (⏎), *Copy PID* (⌘C), *Reveal in Finder*, *Quit…* / *Force Quit…* (own processes only).
4. **History:**
   - a 7-day and 30-day awake-hours chart, session count, and top reasons;
   - kWh and $ per day and month;
   - the sleep/wake log;
   - a session list (start, end, reasons, source).
5. **Settings:**
   - Launch at login (`SMAppService.mainApp`)
   - Global shortcut (default ⌃⌥⌘E, Carbon `RegisterEventHotKey`, needs no Accessibility permission)
   - Menu-bar readout
   - Default policy
   - Presets editor
   - Heads-up lead time
   - Electricity rate
   - Safety cap
   - Thermal auto-release
   - Automation URL toggle
   - Export/import settings (JSON)
   - Reset

### 7.4 Floating HUD

- A borderless, non-activating `NSPanel` at the floating level, shown on all Spaces.
- **Contents:** a ring, the countdown and a compact stat line.
- **Behavior:**
  - it can be dragged anywhere and remembers its position;
  - it snaps to screen corners;
  - it fades to 40% opacity when the mouse isn't over it;
  - optional click-through mode.

### 7.5 Notifications

Posted via `UserNotifications`:

| Notification | Actions |
|---|---|
| Heads-up N min before the last hold ends | **+30m / +1h / ∞** |
| Trigger started / released (per-trigger opt-in) | none |
| Safety cap or thermal release | none |
| Accepted automation command | none |

## 8. Storage

All files live in `~/Library/Application Support/EyesUpGuardian/`, are JSON, and are written atomically:

| File | Contents | Cap |
|---|---|---|
| `settings.json` | Settings | — |
| `triggers.json` | Saved triggers | — |
| `holds.json` | Active holds for restore | — |
| `history.json` | Sessions, sleep/wake events, daily energy buckets | 90 days; older entries pruned on launch and daily |

- Every file carries a `schemaVersion`.
- **Undecodable files** are renamed to `*.corrupt-<timestamp>.json` and replaced with defaults, and the user is notified once. The app never crashes on bad data.

## 9. Security model

1. **No command execution.** No `Process`, `NSTask`, `system`, `posix_spawn`, `popen`, or AppleScript/`NSAppleScript`. A test scans the sources and fails if any of these symbols appear.
2. **No privilege escalation.** No `sudo`, `AuthorizationExecuteWithPrivileges`, privileged helpers or SMJobBless.
3. **No network.** No `URLSession`, `Network.framework` connections or sockets. Enforced by the same source-scan test. The Info.plist declares no network usage.
4. **Zero third-party dependencies.** `Package.swift` has no `dependencies`, and a test asserts this.
5. **All external input is validated:**
   - PIDs: `Int32 > 0` and alive at capture time;
   - durations: bounded;
   - URL commands: allow-list (§5.1);
   - settings files: decoded with bounds checks;
   - bundle IDs and process names: length-limited and treated as opaque strings.
6. **Process quit safety:**
   - only processes whose UID equals the current user's;
   - always a confirmation dialog naming the process and PID;
   - `ProcessIdentity` is re-verified immediately before sending `SIGTERM` (Quit) or `SIGKILL` (Force Quit);
   - never exposed to automation.
7. **Hardened Runtime** is enabled in the ad-hoc signature, with no entitlements beyond the defaults. The app is not sandboxed (App Sandbox blocks IOKit/SMC access). This is documented in `SECURITY.md`.
8. **`SECURITY.md`** lists every system interface the app touches and why, the reporting process, and the threat model: a local malicious app or web page trying to abuse the URL scheme or settings files.

## 10. Testing

- **Unit tests (`EyesUpCoreTests`, Swift Testing framework),** with all OS access behind fakes. Swift Testing ships with the command-line tools; XCTest does not, so XCTest is not used.
  - Hold registry and engine reconciliation: union/diff, assertion naming, at most one assertion per type.
  - Deadlines: earliest-deadline arming, grace periods, heads-up timing, clock jumps (using a fake `Clock`).
  - Process identity: PID-reuse detection, restore rules.
  - Triggers: each condition; hysteresis for CPU/network/disk; schedules crossing midnight, DST and timezone changes; pause-all.
  - The URL parser: valid commands, rejection of everything else, and duration caps.
  - The store: round-trips, corrupt-file recovery, history pruning.
  - The sampler: subscribe/unsubscribe lifecycle, zero subscribers means no timer, and ring buffer bounds.
  - Security scans: forbidden symbols, and no package dependencies.
- **Integration tests** (tagged, run by `make test-integration`): take a real assertion, verify it appears in `IOPMCopyAssertionsByProcess` with the expected name, release it, and verify it's gone. Watch a real short-lived child test process for exit. (The *test* may spawn a process; the app never does.)
- **Performance:** `make perf` launches the built app, waits 30 s, samples its CPU and RSS for 60 s via `proc_pid_rusage`, and fails if above the §3 targets.
- **Manual checklist** (`docs/manual-test-checklist.md`):
  - every UI surface;
  - Reduce Motion and Reduce Transparency;
  - VoiceOver;
  - crash-and-relaunch restore (kill -9 the app, confirm assertions vanish, relaunch and confirm the holds are restored);
  - the heads-up notification actions;
  - launch at login.

## 11. Build, run, publish

- **Toolchain:** Swift 6.x command-line tools (no Xcode). `Package.swift` sets platform `.macOS("26.0")` and Swift 6 language mode.
- **`make` targets:**
  - `make app`: `swift build -c release`, then `Scripts/bundle.sh` assembles `build/EyesUpGuardian.app` (Info.plist with `LSUIElement = YES`, icon, binary) and ad-hoc signs it with Hardened Runtime.
  - `make test`, `make test-integration`, `make perf`.
  - `make install`: copies to `/Applications`.
  - `make clean`.
- **GitHub:**
  - `README.md` (features, screenshots, build steps, first-launch right-click → Open note, unavailable-stat list);
  - `LICENSE` (MIT), `SECURITY.md`, `CONTRIBUTING.md`;
  - `.github/workflows/ci.yml` (build + unit tests on a macOS runner).
- **Future notarization:** `Scripts/release.sh` is structured with a signing identity variable and a `notarytool` step that is skipped when no identity is configured. Adding a Developer ID later requires no restructuring.

## 12. Out of scope (v1)

- Running commands on the user's behalf (`caffeinate <utility>`)
- Desktop widgets (would require an Xcode target; can be added later without rewriting the core)
- App Store distribution (incompatible with the IOKit/SMC access in §6.2)
- Intel Mac support for private probes (the app runs, but those stats show as unavailable)
- Localization beyond English
- Network features of any kind (update checks, sync, public IP)
