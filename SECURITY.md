# Security

EyesUpGuardian keeps your Mac awake. That is all it does, and this file lists exactly what it touches so you can check the claims yourself.

## What the app will never do

- **Run commands.** There is no `Process`, `NSTask`, `posix_spawn`, `popen`, `system`, `exec*`, `NSUserUnixTask` or AppleScript anywhere in the app, and it sends no Apple Events.
- **Use the network.** No `URLSession`, no sockets, no listening ports, no DNS, no update checks, no analytics. The running app holds no network connections of any kind — you can check with `lsof`, below.
- **Ask for admin rights.** No `sudo`, no privileged helper, no `SMAppService`, no `setuid`, no privileged XPC.
- **Depend on third-party code.** `Package.swift` has no dependencies, no binary targets, no plugins and no unsafe flags; only Apple frameworks are linked.
- **Write anywhere but its own folder.** Every write goes to `~/Library/Application Support/EyesUpGuardian/`, and its files are created readable only by you (`0600`, in a `0700` folder).
- **Load code at runtime.** No `dlopen`/`dlsym` in app code. (The binary does import `dlsym`: it comes from the Swift toolchain's own OS-version check, not from this app. None of the app's object files reference it.)

**Three things it does do, deliberately, and they are the only exceptions:**

- **Reveal in Finder.** The Processes tab can ask Finder to show a process's file, when you choose it from a menu. That is the single call in the codebase allowed to activate another app.
- **Read one file you picked yourself.** Importing settings reads the file chosen in an open panel, with the same 5 MB cap the app's own files have. It is the one `Data(contentsOf:)` in the codebase.
- **Receive one Apple Event.** The `eyesup://` link arrives as the standard open-URL Apple Event, and macOS installs the usual quit/activate handlers for every app. The app sends none.

The first two are marked in the source with `// security-allow:`, so `grep -rn "security-allow:" Sources/` lists exactly them — two lines, no more.

A test enforces these (`Tests/EyesUpCoreTests/SecurityGuardTests.swift`): it scans every file in `Sources/` for forbidden API spellings — process launching, networking including `bind`/`listen`/`accept`, blind `Data(contentsOf:)`, XPC and Mach lookups, privilege escalation, runtime code loading, inbound channels — and fails the build on a match. It also checks the build scripts fetch nothing and the package declares no dependencies, binary targets, plugins or unsafe flags. Exceptions must be marked on the line that needs one, so they cannot hide. You can verify the built app independently:

```bash
nm -u build/EyesUpGuardian.app/Contents/MacOS/EyesUpGuardian \
  | grep -E '^_(posix_spawn|execv[eplP]*|fork|system|popen|dlopen|socket|connect|bind|listen|accept|setuid|seteuid|setgid)$'
otool -L build/EyesUpGuardian.app/Contents/MacOS/EyesUpGuardian
```

The first command prints nothing but `_dlsym`, which the Swift runtime uses for its own OS-version
check (see above). The patterns are anchored on purpose: an unanchored search for `system` also
matches SwiftUI's `Font.system(size:)` and `Image(systemName:)`, which have nothing to do with
running commands. The second should list only Apple frameworks. To confirm it holds no network connections while running:

```bash
lsof -nP -p "$(pgrep -nx EyesUpGuardian)" | grep -E 'TCP|UDP|IPv4|IPv6'
```

That prints nothing: the app has no sockets at all, not merely no listening ones.

## What it does touch

| Interface | Why |
|---|---|
| IOKit power assertions (`IOPMAssertionCreateWithName`) | Keeping the Mac awake. This is what `caffeinate` uses. |
| IOKit power sources (`IOPSNotificationCreateRunLoopSource`) | The "while on AC power" trigger. |
| `IOBlockStorageDriver` registry statistics | The "while the disk is busy" trigger. |
| CoreGraphics display list and reconfiguration callback | The "while a display is connected" trigger. |
| `host_statistics`, `sysctl` (`NET_RT_IFLIST2`) | CPU and network activity triggers. |
| libproc (`proc_listallpids`, `proc_pidinfo`, `proc_pidpath`, `proc_name`) | Watching a process until it exits, the "while a command is running" trigger, and the process table. Other users' processes appear in the table the way they do in Activity Monitor — a name and, where macOS allows it, a path; only your own can be watched, signalled, or have their details read in full. Processes whose path macOS won't reveal are grouped as "Other" rather than guessed at. |
| kqueue process source | Instant notice that a watched process exited. |
| `NSWorkspace` running applications and launch/quit notifications | The "while an app is open" trigger. |
| `UserNotifications` | The heads-up before your Mac may sleep, and trigger notices. |
| AppleSMC user client (`IOConnectCallStructMethod`) | Power draw, fan speed and temperature. Read-only: the app only ever reads keys, never writes them. |
| `IOAccelerator` registry statistics | GPU utilization. |
| `host_processor_info`, `host_statistics64` | CPU and memory. |
| `proc_pid_rusage`, `proc_pidinfo` | The process table's CPU and memory columns. |
| `kill(2)` | Quit / Force Quit, for your own processes only, after re-checking the process identity. |

None of these needs admin rights. You can see what the app is holding at any time:

```bash
pmset -g assertions | grep EyesUpGuardian
```

## Sandboxing and signing

The app is **not** sandboxed, because the App Sandbox blocks the IOKit access the triggers need. It runs with the Hardened Runtime enabled and no extra entitlements, and is ad-hoc signed when you build it yourself. This also means it cannot ship on the Mac App Store.

## Threat model

The app assumes anything it reads from disk or receives through a link is hostile.

**Files.** `holds.json`, `triggers.json` and `settings.json` can be written by any process running as you. Every value is range-checked before it is used: unknown policy bits are masked off, labels and identifiers are length-limited, dates in the future are rejected, activity thresholds have floors, saved shapes the app itself cannot create are refused, and the number of saved sessions (64) and triggers (64) is capped *before* the file is validated, so a huge file costs no more work than a normal one. A file that is corrupt, truncated, oversized or from a newer version is moved aside — keeping only the newest two copies — and the app starts clean with a notice.

Each file is opened directly, refusing symlinks (`O_NOFOLLOW`) and anything that is not a regular file, and the size is checked on the descriptor actually read. Without that, a symlink planted in place of one of these files would report its own tiny size and then feed the app whatever it pointed at.

Control **and** formatting characters — bidirectional overrides, zero-width joiners, soft hyphens — are stripped from every name that reaches an assertion name, a notification, the menu bar or the process table. A tampered file therefore cannot forge a line in `pmset -g assertions`, reverse how a name reads, or put a fake message in a notification that appears to come from this app.

**Links.** The `eyesup://` scheme is **off by default**. When you switch it on, a link can do exactly three things: start, extend or stop *its own* session. It can never cancel a session you started by hand, never run longer than 24 hours or your safety cap (whichever is lower), and never reach anything else. Links with a path, credentials, a port, a fragment, duplicate or unexpected parameters, non-ASCII digits or whitespace are rejected.

**Quitting a process.** Quit and Force Quit are offered only for processes you own. The process's identity (its PID *and* its start time, captured when the row was sampled) is re-checked immediately before the signal, so a PID reused between the click and the signal is refused rather than killed. A microsecond-wide window remains between that check and `kill(2)` itself, which macOS offers no way to close.

**What this does not protect against.** A process running as you can already keep the Mac awake by itself (for example by running `caffeinate`), so the app cannot be a boundary against code that is already running as you. What it does guarantee is that EyesUpGuardian itself never becomes a way to do more than that.

## Reporting a problem

Open an issue describing what you observed and how to reproduce it. If you would rather not do that in public, say so in the issue without the details and we will find another way.
