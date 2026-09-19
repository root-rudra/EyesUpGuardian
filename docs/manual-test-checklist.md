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
