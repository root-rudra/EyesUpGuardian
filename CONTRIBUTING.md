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

The app must stay at **under 0.1% CPU and 30 MB when idle in its default configuration** — `make perf` checks it. Measure on an otherwise idle Mac; a run started while a build is still finishing reports the machine, not the app. Visible surfaces (dashboard, HUD, stats in the menu bar) are allowed up to 1.5%; `make perf-stats` measures that configuration.
