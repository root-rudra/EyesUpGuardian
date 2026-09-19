# Security

EyesUpGuardian keeps your Mac awake. That is all it does, and this file lists exactly what it touches so you can check the claims yourself.

## What the app will never do

- **Run commands.** There is no `Process`, `NSTask`, `posix_spawn`, `popen`, `system`, `exec*`, AppleScript or Apple Event anywhere in the app. It does not launch other apps or load code at runtime.
- **Use the network.** No `URLSession`, no sockets, no update checks, no analytics.
- **Ask for admin rights.** No `sudo`, no privileged helper, no `SMAppService`, no `setuid`.
- **Depend on third-party code.** `Package.swift` has no dependencies; only Apple frameworks are linked.
- **Touch files outside its own folder.** It reads and writes only `~/Library/Application Support/EyesUpGuardian/`.

A test enforces the first four (`Tests/EyesUpCoreTests/SecurityGuardTests.swift`): it scans every source file for forbidden API spellings and fails the build on a match, and it checks that the package has no dependencies. You can verify the built app independently:

```bash
nm -u build/EyesUpGuardian.app/Contents/MacOS/EyesUpGuardian | grep -E 'posix_spawn|execv|fork|system|popen|dlopen|socket|connect|setuid|NSTask|URLSession'
otool -L build/EyesUpGuardian.app/Contents/MacOS/EyesUpGuardian
```

The first command should print nothing. The second should list only Apple frameworks.

## What it does touch

| Interface | Why |
|---|---|
| IOKit power assertions (`IOPMAssertionCreateWithName`) | Keeping the Mac awake. This is what `caffeinate` uses. |
| IOKit power sources (`IOPSNotificationCreateRunLoopSource`) | The "while on AC power" trigger. |
| `IOBlockStorageDriver` registry statistics | The "while the disk is busy" trigger. |
| CoreGraphics display list and reconfiguration callback | The "while a display is connected" trigger. |
| `host_statistics`, `sysctl` (`NET_RT_IFLIST2`) | CPU and network activity triggers. |
| libproc (`proc_listallpids`, `proc_pidinfo`, `proc_pidpath`, `proc_name`) | Watching a process until it exits, and the "while a command is running" trigger. Only your own processes are visible. |
| kqueue process source | Instant notice that a watched process exited. |
| `NSWorkspace` running applications and launch/quit notifications | The "while an app is open" trigger. |
| `UserNotifications` | The heads-up before your Mac may sleep, and trigger notices. |

None of these needs admin rights. You can see what the app is holding at any time:

```bash
pmset -g assertions | grep EyesUpGuardian
```

## Sandboxing and signing

The app is **not** sandboxed, because the App Sandbox blocks the IOKit access the triggers need. It runs with the Hardened Runtime enabled and no extra entitlements, and is ad-hoc signed when you build it yourself. This also means it cannot ship on the Mac App Store.

## Threat model

The app assumes anything it reads from disk or receives through a link is hostile.

**Files.** `holds.json`, `triggers.json` and `settings.json` can be written by any process running as you. Every value is range-checked before it is used: unknown policy bits are masked off, labels and identifiers are length-limited, dates in the future are rejected, activity thresholds have floors, and the number of saved sessions (64) and triggers (64) is capped. A file that is corrupt, truncated, oversized or from a newer version is moved aside and the app starts clean with a notice. Control characters are stripped from anything that reaches an assertion name, so a tampered file cannot forge lines in `pmset -g assertions`.

**Links.** The `eyesup://` scheme is **off by default**. When you switch it on, a link can do exactly three things: start, extend or stop *its own* session. It can never cancel a session you started by hand, never run longer than 24 hours or your safety cap (whichever is lower), and never reach anything else. Links with a path, credentials, a port, a fragment, duplicate or unexpected parameters, non-ASCII digits or whitespace are rejected.

**What this does not protect against.** A process running as you can already keep the Mac awake by itself (for example by running `caffeinate`), so the app cannot be a boundary against code that is already running as you. What it does guarantee is that EyesUpGuardian itself never becomes a way to do more than that.

## Reporting a problem

Open an issue describing what you observed and how to reproduce it. If you would rather not do that in public, say so in the issue without the details and we will find another way.
