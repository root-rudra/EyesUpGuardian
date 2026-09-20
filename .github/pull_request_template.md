## What this changes

<!-- One or two sentences. If it fixes an issue, write "Fixes #123". -->

## How it was tested

<!-- `make test` output, and what you did by hand. New behaviour needs a test that failed before. -->

## The rules this project keeps

- [ ] No process launching, network access, privilege escalation or runtime code loading — `make test` enforces this and fails the build on a match
- [ ] No new third-party dependencies
- [ ] No SwiftUI `@State` (its macro plugin ships only with full Xcode; use `@Observable` + `@Bindable`)
- [ ] `make perf` still passes if this touches sampling, timers or the menu bar
