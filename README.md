# EyesUpGuardian

A native macOS menu-bar app that keeps your Mac awake. It's a safe, clickable replacement for `caffeinate` and Amphetamine.

- Timers, indefinite, until a time, or until a process exits (kernel-notified, PID-reuse safe)
- Every `caffeinate` sleep type: system (`-i`), display (`-d`), disk (`-m`), system on AC (`-s`), user-activity nudge (`-u`)
- A draining-ring menu-bar icon, an Ambient popover, and a heads-up notification before your Mac may sleep
- If the app crashes, macOS releases the hold automatically, so your Mac is never stuck awake

## Automatic keep-awake

Triggers keep your Mac awake by themselves. Open the dashboard (right-click the menu-bar icon → Open Dashboard…) and add any of:

- **While an app is open** — for example Claude, Xcode or Docker
- **While a command is running** — for example `node`, `claude` or `swift-build` (your own processes only; macOS hides other users' processes)
- **On a schedule** — chosen weekdays and times, including windows that cross midnight
- **While the Mac is busy** — CPU, network or disk above a threshold you set
- **While a display is connected**, or **while on AC power**

Each trigger can keep the display on too, stay awake for a grace period after its condition ends, and notify you when it starts and stops. Pause them all from the Triggers tab.

## What your Mac is doing

The dashboard's **Overview** shows CPU (with performance and efficiency core averages), memory and pressure, power draw in watts, temperature, fan speed, GPU use, disk, network, uptime, load and thermal state — plus **which other apps are keeping your Mac awake**, which is usually the answer to "why won't it sleep?".

**Processes** lists what's running, sorted by CPU or memory, with a filter. Right-click any row to keep your Mac awake until that process exits, copy its PID, reveal it in Finder, or quit it (your own processes only, with a confirmation).

You can also put live stats in the menu bar next to the timer, and pin a small floating **HUD** that stays visible over other apps.

Everything is measured only while you're looking at it: close the dashboard and the popover, and the app goes back to measuring nothing.

**What needs no admin rights, and what isn't available:** power draw, fan speed and temperature come from the Mac's own sensors and work without a password. The per-chip power split (CPU vs GPU vs Neural Engine) is *not* included, because reading it needs a private interface this app deliberately avoids; the total is shown instead. Any reading your Mac doesn't provide shows as "—" rather than a made-up number.

**Safety guards** (Settings): never stay awake longer than a chosen number of hours, and let the Mac sleep if it gets too hot.

**Automation link** (off by default): once enabled, scripts can run `open "eyesup://start?for=2h"`, `eyesup://extend?by=30m` and `eyesup://stop`. Links can only touch their own session, never longer than 24 hours.

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
