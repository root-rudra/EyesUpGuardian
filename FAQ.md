# EyesUpGuardian — FAQ

A free, open-source macOS menu bar app that keeps your Mac awake and shows you what it's doing.
It replaces the `caffeinate` command with something you can click, and it replaces
Amphetamine-style keep-awake apps with something whose entire source you can read in an afternoon.

- [What it is](#what-it-is)
- [Keeping your Mac awake](#keeping-your-mac-awake)
- [System stats](#system-stats)
- [How lightweight is it, really?](#how-lightweight-is-it-really)
- [Privacy](#privacy)
- [Security](#security)
- [Installing without the App Store](#installing-without-the-app-store)
- [Permissions](#permissions)
- [Troubleshooting](#troubleshooting)
- [Feedback, bugs and feature requests](#feedback-bugs-and-feature-requests)

---

## What it is

**In one line:** a menu bar app that stops your Mac going to sleep — on a timer, indefinitely, on a
schedule, or automatically while a particular app or command is running — and shows CPU, memory,
power draw, temperature, fans, GPU, disk, network and the full process list while it does.

**Who it's for:** anyone who runs long builds, renders, downloads, backups, AI agents or transfers
and is tired of the screen sleeping halfway through — and anyone who wants to know *why* their Mac
won't sleep, which this app answers directly by listing the other apps holding it awake.

**What it costs:** nothing. MIT licensed, no account, no subscription, no telemetry, no in-app
purchase, no "pro" tier.

### How is it different from the `caffeinate` command?

`caffeinate` is excellent and it is what this app uses underneath — the same IOKit power assertions,
not a shell wrapper around the command. What the app adds:

| | `caffeinate` | EyesUpGuardian |
|---|---|---|
| Start a 2-hour session | remember the flags, keep a terminal open | click a preset |
| See what's holding it | `pmset -g assertions`, and read carefully | it's in the menu bar and the popover |
| Stop it | find the terminal, Ctrl-C | click Stop |
| Keep awake while Docker runs | write a script | add a trigger |
| Safety net | none — a forgotten terminal keeps the Mac awake for days | a cap you set, and a thermal release |
| Know what it cost you | — | the History tab, in kWh and in money |

### How is it different from Amphetamine and similar apps?

The differences that matter are the ones you can check yourself: this app has **no network code at
all** (not "we promise not to phone home" — there are no sockets in the binary), **zero third-party
dependencies**, and a test that **fails the build** if a forbidden API ever appears in the source.
See [SECURITY.md](SECURITY.md) for the commands to verify each claim on your own machine.

---

## Keeping your Mac awake

**Sessions you start yourself**

- For a preset length (15 minutes, 1, 2, 4 hours — the presets are editable)
- For a duration you type: `45m`, `2h`, `1h 30m`
- Until a time today
- Indefinitely, until you stop it
- Until a process exits — pick it from the process table, or paste a PID

**Automatic triggers**

- **While an app is open** — Claude, Xcode, Docker, Final Cut, anything
- **While a command is running** — `node`, `ffmpeg`, `swift-build`, your own scripts
- **On a schedule** — chosen weekdays and times, including windows that cross midnight
- **While the Mac is busy** — CPU, network or disk above a threshold you set
- **While a display is connected**
- **While on AC power**

Each trigger can also keep the display on, stay awake for a grace period after its condition ends,
and notify you when it starts and stops. You can pause them all with one switch.

**Every sleep type `caffeinate` offers**

| Flag | What it does | Where |
|---|---|---|
| `-i` | prevent idle system sleep | every session |
| `-d` | keep the display on | a toggle on each session and trigger |
| `-m` | prevent the disk idling | Settings → Sleep types |
| `-s` | prevent sleep only while on AC power | Settings → Sleep types |
| `-u` | wake the display now | "Wake display" in the popover |

**Safety**

- A cap you choose (1–48 hours): nothing keeps your Mac awake longer than that, including links
- Optional thermal release: if the Mac gets too hot, the hold is dropped
- A heads-up notification before a session ends, with "+30 min", "+1 hour" and "Indefinitely"
- If the app ever crashes, macOS releases the hold by itself — your Mac cannot get stuck awake

**Shortcuts and automation**

- **⌃⌥⌘E** toggles keeping awake from anywhere, with no accessibility permission needed
- **⌘1–⌘5** switch dashboard tabs
- `eyesup://start?for=2h`, `eyesup://extend?by=30m`, `eyesup://stop` for scripts — **off by
  default**, and a link can only touch its own session

---

## System stats

**Overview:** CPU (with performance and efficiency core averages), memory and memory pressure, power
draw in watts, temperature, fan speed, GPU utilization, disk read/write, network throughput, uptime,
load average, thermal state — and **which other apps are keeping your Mac awake**, which is usually
the answer to "why won't it sleep?".

**Processes:** a native table with sortable columns, search, real app icons, and rows grouped into
**macOS** (shipped with the system, from the protected system volume) and **Installed** (everything
you or an installer put there). Right-click a row to keep the Mac awake until that process exits,
copy its PID, reveal it in Finder, or quit it — your own processes only, with a confirmation, and
the app re-checks the process's identity immediately before signalling so a recycled PID is never
hit by mistake.

**History:** how long your Mac was kept awake each day, what kept it awake, how many sessions, the
energy drawn in kilowatt-hours, and what that cost if you enter an electricity rate. Plus a log of
when your Mac actually slept and woke.

**Floating HUD:** a small always-on-top panel with the countdown, a draining ring and a compact stat
line. It snaps to a corner, fades when your pointer is elsewhere, and can let clicks pass through.

**Menu bar:** the icon alone, the time left, or the time plus CPU, memory, power, temperature or
network.

### Which stats need special hardware?

Power draw, fan speed and temperature come from the Mac's own sensors (the SMC) and need no
password. Any reading your Mac doesn't provide shows as **—** rather than a made-up number. The
per-chip power split (CPU vs GPU vs Neural Engine) is deliberately **not** included: reading it
needs a private interface loaded at runtime, which this app refuses to do. The system total is shown
instead.

---

## How lightweight is it, really?

Measured on the reference Mac (M3 Ultra Mac Studio, macOS 26) with `make perf`, which anyone can run:

| What's on screen | CPU | Memory |
|---|---|---|
| Menu bar only, default settings | **0.000–0.017%** of one core | **17 MB** |
| HUD pinned + CPU and power in the menu bar | 0.75% | 21 MB |
| Dashboard open, Overview | 1.5–1.7% | 35 MB |
| Dashboard open, Processes (5 s refresh) | 1.3% | 56 MB |

Why it stays that low:

- **It measures only what you're looking at.** Close the dashboard and the popover and sampling
  stops. The one exception is the energy tally (a power reading every 30 seconds), and you can turn
  that off in Settings — then it measures nothing at all.
- **Each metric has its own cadence.** The expensive probes (GPU, disk, the process list) run far
  less often than CPU and memory, instead of everything being dragged to the fastest rate.
- **The process table refreshes every 5 seconds by default** — the same as Activity Monitor. You can
  set 1, 2, 5 or 10 seconds; 1 second costs about four times as much CPU, and the app says so.
- **One process.** No background daemon, no helper tool, no launch agent, nothing running when the
  app is quit.
- **Zero dependencies.** Only Apple frameworks are linked, so there's no framework bloat to carry.

There's a build gate for this: `make perf` fails if the idle configuration exceeds **0.1% CPU or
30 MB**, so a change that makes the app heavier doesn't get committed quietly.

---

## Privacy

**Nothing leaves your Mac. There is nowhere for it to go.**

- **No network code.** No `URLSession`, no sockets, no DNS, no update check, no crash reporting, no
  analytics, no "anonymous usage statistics". The running app holds no network connections at all —
  not just no *listening* ports. Check it yourself while the app is running:

  ```bash
  lsof -nP -p "$(pgrep -nx EyesUpGuardian)" | grep -E 'TCP|UDP|IPv4|IPv6'
  ```

  That prints nothing.

- **No account, no sign-in, no licence key.** The app doesn't know who you are.
- **Everything it stores stays in one folder**, `~/Library/Application Support/EyesUpGuardian/`,
  in files readable only by you (`0600`, in a `0700` folder): your settings, your triggers, the
  current hold, and your history. Delete the folder and the app starts fresh.
- **Your history is yours.** Sessions, sleep/wake events and energy days are kept for 90 days and
  never sent anywhere. "Clear history" empties it, with a confirmation.
- **Export/import is a plain JSON file** you choose the location of.
- **No screen recording, no keystroke logging.** The global shortcut uses a system hot key that
  reports only that one combination — the app never sees what else you type, which is why it needs
  no accessibility permission.
- **Process names stay local.** The app reads the process list the same way Activity Monitor does,
  to show it to you. Nothing about it is transmitted, because nothing can be.

---

## Security

The short version, in full detail in [SECURITY.md](SECURITY.md):

- **It never runs commands.** No `Process`, `NSTask`, `posix_spawn`, `popen`, `system`, `exec*`, no
  shell, no AppleScript. Nothing you type can become a command, because there is no command to run.
- **It never asks for admin rights.** No `sudo`, no privileged helper, no setuid, no privileged XPC.
- **It never loads code at runtime.** No `dlopen`, no plugins, no bundles.
- **It has no dependencies.** `Package.swift` declares none — no third-party code, no supply chain.
- **It writes only inside its own folder.**
- **Everything it reads is treated as hostile**: saved files are range-checked and size-capped before
  use, text is stripped of control and direction-changing characters, and automation links are
  parsed strictly and clamped to your safety cap.

These aren't promises in a README — a test (`Tests/EyesUpCoreTests/SecurityGuardTests.swift`) scans
every source file for forbidden API spellings and **fails the build** on a match, including in the
build scripts. Exceptions must be marked on the line that needs one, so they can't hide. There is
currently exactly one, for "Reveal in Finder".

**Is it sandboxed?** No, and this is deliberate: the App Sandbox blocks the IOKit access the triggers
and sensors need. It runs with the Hardened Runtime and no extra entitlements. This is also why it
can't be on the Mac App Store.

---

## Installing without the App Store

This app isn't on the Mac App Store and can't be — see above. There are two ways to get it, and
neither involves an account.

**Build it yourself** (recommended — you get a copy signed by your own machine, which opens normally):

```bash
git clone https://github.com/<owner>/EyesUpGuardian.git
cd EyesUpGuardian
make install
open /Applications/EyesUpGuardian.app
```

You need macOS 26 or later and the Xcode Command Line Tools (`xcode-select --install`). Full Xcode is
not required.

**Or download the .dmg** from the Releases page, drag the app to Applications, then **right-click it
→ Open** the first time. macOS shows that prompt for any app not notarized by a paid Apple Developer
account; the project may be notarized later, and the release script already supports it.

**To uninstall:** quit the app, drag it to the Trash, and delete
`~/Library/Application Support/EyesUpGuardian/`. There is nothing else — no daemon, no login item you
didn't enable, no files anywhere else.

---

## Permissions

| Permission | Needed? |
|---|---|
| Accessibility | **No** — the global shortcut is a system hot key, not a keystroke watcher |
| Screen Recording | **No** |
| Full Disk Access | **No** |
| Notifications | Optional — only for the heads-up before sleep and trigger notices |
| Open at login | Optional — a toggle in Settings, using Apple's own `SMAppService` |

You can see everything it's holding at any time:

```bash
pmset -g assertions | grep EyesUpGuardian
```

---

## Troubleshooting

**"EyesUpGuardian can't be opened because Apple cannot check it for malicious software."**
Right-click the app → **Open** → **Open**. That's macOS asking about notarization, not about
anything the app does. Building it yourself avoids the prompt entirely.

**Power, temperature or fan readings show "—".**
Your Mac's SMC doesn't expose those keys, or the machine has no fans. The app shows a dash rather
than inventing a number.

**The ⌃⌥⌘E shortcut doesn't work.**
Another app has claimed that combination. Settings says so in orange when that happens; turn the
shortcut off there, or quit the other app.

**My Mac still went to sleep.**
Check `pmset -g assertions`: a *forced* sleep (closing the lid on a Mac without clamshell power, or
choosing Sleep from the Apple menu) overrides every assertion, by design — no app can prevent that.
Also check whether your safety cap or the thermal release ended the session; both leave a notice.

**The dashboard feels heavy on an older Mac.**
Set the Processes tab's **Update** menu to 10 seconds, and close the dashboard when you're not
reading it. The menu bar and HUD keep working either way.

---

## Feedback, bugs and feature requests

Yes — GitHub has both, and this project uses them:

- **[Issues](../../issues)** — bug reports and concrete, actionable requests. There are two forms to
  pick from, so you don't have to guess what to include.
- **[Discussions](../../discussions)** — questions, ideas and "would it be possible to…". Ideas that
  get traction become issues. Discussions also have comment threads and reactions, so you can vote
  for something instead of filing a duplicate.

Both need a free GitHub account. Please don't include personal information, screenshots of private
work, or anything from a machine you don't own.

**Security problems:** open an issue saying you've found one *without the details*, and we'll find a
private channel. Please don't post a working exploit publicly.
