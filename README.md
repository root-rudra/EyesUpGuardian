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
