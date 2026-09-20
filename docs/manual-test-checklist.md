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


## Triggers (Plan 2)
- [ ] Suggestion card appears for a running known app and adds a working trigger.
- [ ] App trigger: quitting and relaunching the app releases and re-takes the hold.
- [ ] Process trigger: `sleep 120` in Terminal takes the hold within ~10 s and releases within ~10 s of ending.
- [ ] Schedule trigger: activates and releases at the times set, including a window that crosses midnight.
- [ ] CPU trigger: a heavy build takes the hold after the "busy for" time, and it clears after the quiet time.
- [ ] Grace period keeps the Mac awake for the set minutes after the condition ends.
- [ ] Editing a trigger's condition swaps its monitor; deleting it clears the hold.
- [ ] Pause for 1 hour clears trigger holds; Resume re-takes them for conditions that are still true.
- [ ] A trigger with notifications on posts a banner when it starts and stops.

## Safety guards (Plan 2)
- [ ] Setting "never stay awake longer than 1 hour" ends an indefinite session after an hour with a banner.
- [ ] With the cap off, an indefinite session shows no end time again.

## Automation link (Plan 2)
- [ ] With links off, `open "eyesup://start?for=1h"` does nothing and explains why.
- [ ] With links on: start, extend and stop all work, and `eyesup://quit` is refused.
- [ ] `eyesup://stop` does not cancel a session started by hand.


## Stats and dashboard (Plan 3)
- [ ] Popover shows four tiles (CPU, Memory, Power, Uptime) updating about once a second.
- [ ] Closing the popover stops the updates (Activity Monitor: CPU back to ~0%).
- [ ] Overview: countdown, three sparklines filling over ~10 s, twelve tiles with real values.
- [ ] Power and fan tiles show numbers on this Mac (Mac Studio). On hardware without them, they read "—".
- [ ] Other apps holding the Mac awake are listed, in the popover and in Overview.
- [ ] Processes: sorted by CPU, filter works, sort switches, right-click offers Copy PID / Reveal / Keep awake until this exits.
- [ ] Quit is offered only for your own processes, asks for confirmation, and reports the outcome.
- [ ] Quitting a process that already ended says so instead of signalling anything.
- [ ] Menu-bar readout options each show what they promise; "Icon only" and "Icon and time left" measure nothing.
- [ ] HUD pins, drags, survives a relaunch in the same place, floats over full-screen apps, and stops sampling when unpinned.
- [ ] `make perf` passes in the default configuration (measured 0.000% CPU, 16 MB).
- [ ] Measured cost of the visible extras (all well under the 1.5% budget for a visible surface, and
      about 0.03% of this 32-core Mac): HUD pinned with nothing counting down 0.30%; HUD pinned while a
      timer runs ~1.1%; menu-bar stat readout ~0.4%.
- [ ] Dashboard open: CPU under 1.5% in Activity Monitor.

## Plan 4
- [ ] Press **⌃⌥⌘E** with another app focused: the menu-bar ring fills and `pmset -g assertions | grep EyesUpGuardian` shows a hold. Press it again: the ring empties and the line goes away.
- [ ] Turning the Settings toggle off releases the key (another app can claim it); turning it back on reclaims it. If the key is already taken at launch, Settings says so in orange.
- [ ] ⌘1–⌘5 switch dashboard tabs in sidebar order (Overview, Triggers, Processes, History, Settings).
- [ ] Pin the HUD, drag it near the middle: it snaps to the nearest corner about a third of a second after you let go.
- [ ] With the pointer elsewhere the HUD sits at 40% opacity; hovering fades it back to full.
- [ ] With a timer running, the HUD's ring drains in step with the menu-bar one.
- [ ] Settings → "Let clicks pass through it": clicks land on the window behind the HUD.
- [ ] Right-clicking the menu-bar icon while the HUD is pinned reads **Unpin HUD**.

## History, settings and shortcuts (Plan 4)
- [ ] A finished session appears in History with the right duration and reasons.
- [ ] Quitting while awake still records the session.
- [ ] The per-day chart matches what you did; switching 7/30 days changes it.
- [ ] With an electricity rate set, History shows money; with it empty, kWh only.
- [ ] Sleep and wake are logged when the Mac actually sleeps.
- [ ] Clear history empties the tab and the file.
- [ ] Preset toggles in Settings change the popover's buttons immediately.
- [ ] Export settings writes a file; Import restores it; importing rubbish is refused and changes nothing.
- [ ] Open at login: the toggle matches System Settings → Login Items, both ways.
- [ ] About shows the icon and version; the app icon appears in Finder.
- [ ] `make perf` passes (default configuration, on an idle Mac); `make perf-stats` stays under 1.5% (measured 0.750% with the HUD pinned and CPU + power in the menu bar).
- [ ] Settings → Sleep types: with "also keep the disk awake" on, a new session shows `PreventDiskIdle` in `pmset -g assertions`.
- [ ] Settings → Track energy off: `lsof`/Activity Monitor show no sampling while no window is open, and History stops gaining energy.
- [ ] Reset settings asks first, then restores defaults, leaving triggers and history alone.
- [ ] With only a trigger holding the Mac awake, ⌃⌥⌘E pauses the triggers (and pressing it again resumes them).
- [ ] With an indefinite session running, the popover offers no "+30m"; the heads-up notification's +30 min explains why instead of doing nothing.

## Processes tab (grouping, fonts, native look)
- [ ] With **All** selected, rows sit under **macOS**, **Installed** and (if any) **Other** headings, each with a count.
- [ ] **macOS** and **Installed** show only that kind; searching inside a group never falls back to everything.
- [ ] Clicking a column header sorts by it, and clicking again reverses it.
- [ ] Right-clicking the column header offers the columns, including **Kind**, which starts hidden.
- [ ] Rows show real app icons; processes without a readable path show the group's symbol instead.
- [ ] Settings → Process list changes the table's font and size immediately.
- [ ] The **Update** menu changes the refresh rate; 5s is the default (Activity Monitor's own).
- [ ] Opening the app again while it runs (Finder, Spotlight, `open -a`) shows the dashboard on the tab you left it on.
- [ ] Dashboard open: Overview ~1.5-1.7% CPU, Processes ~1.3% at 5s, ~5% at 1s.
