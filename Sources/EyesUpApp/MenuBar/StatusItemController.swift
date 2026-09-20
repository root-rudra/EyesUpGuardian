import AppKit
import EyesUpCore
import SwiftUI

/// Owns the menu-bar item. Left-click opens the popover; right-click shows quick actions.
@MainActor
final class StatusItemController: NSObject {
    private let controller: AwakeController
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var minuteTimer: Timer?
    private var readout: MenuBarReadout = .timer
    private var stats: StatsViewModel?
    private var statsTimer: Timer?
    private var makePopoverContent: (() -> AnyView)?
    // Rebuilding the icon and reassigning the title force a menu-bar re-layout, which costs far more
    // than sampling does. Both are cached so a refresh that changes nothing does nothing.
    private var drawnIcon: (active: Bool, step: Int)?
    private var drawnTitle: String?
    private var drawnToolTip: String?
    /// Set by the app delegate; shows the dashboard window.
    var onOpenDashboard: (() -> Void)?
    /// Set by the app delegate; pins or unpins the floating HUD.
    var onToggleHUD: (() -> Void)?
    var onIsHUDPinned: (() -> Bool)?
    var onIsPaused: (() -> Bool)?

    init(controller: AwakeController) {
        self.controller = controller
        super.init()
        popover.behavior = .transient
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: 0, weight: .regular) // 0 = default menu-bar size
        }
        observeController()
        refresh()
    }

    /// The popover's content is built when it opens and torn down when it closes. A hosting
    /// controller that lives while the popover is hidden keeps re-rendering on every metrics
    /// update, which costs far more than the sampling itself.
    func setPopoverContent<Content: View>(_ makeView: @escaping () -> Content) {
        makePopoverContent = { AnyView(makeView()) }
    }

    /// Switches the readout. Stat readouts sample every 2 s (spec §3); the other two sample nothing.
    func applyReadout(_ readout: MenuBarReadout, center: MetricsCenter) {
        self.readout = readout
        stats?.stop()
        statsTimer?.invalidate()
        statsTimer = nil

        if readout.metricIDs.isEmpty {
            stats = nil
        } else {
            let model = StatsViewModel(center: center, ids: readout.metricIDs, interval: 2)
            model.start()
            stats = model
            let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            timer.tolerance = 0.5
            RunLoop.main.add(timer, forMode: .common)
            statsTimer = timer
        }
        refresh()
    }

    func refresh() {
        guard let button = statusItem.button else { return }
        let now = Date()
        let until = controller.awakeUntil
        var fraction: Double?
        if let until, let start = controller.sessionStart {
            fraction = TimeFormatting.remainingFraction(now: now, start: start, end: until)
        }
        // The ring has ~60 visible steps; redraw only when it actually moves.
        let step = Int(((fraction ?? 1) * 60).rounded())
        let iconState = (active: controller.isAwake, step: step)
        if drawnIcon == nil || drawnIcon! != iconState {
            button.image = RingIcon.image(active: controller.isAwake, fraction: fraction)
            drawnIcon = iconState
        }
        var title = readout == .iconOnly ? "" : (until.map { " " + TimeFormatting.menuBar(remaining: $0.timeIntervalSince(now)) } ?? "")
        if let stats, case let text = stats.readoutText(for: readout), !text.isEmpty {
            title += title.isEmpty ? " " + text : " · " + text
        }
        if drawnTitle != title {
            button.title = title
            drawnTitle = title
        }
        var toolTip = controller.isAwake
            ? "EyesUpGuardian: " + controller.holds.map(\.label).joined(separator: ", ")
            : "EyesUpGuardian: your Mac may sleep"
        if onIsPaused?() == true { toolTip += " · triggers paused" }
        if drawnToolTip != toolTip {
            button.toolTip = toolTip
            drawnToolTip = toolTip
        }
        updateMinuteTimer(needed: until != nil)
    }

    // MARK: Observation and timing

    private func observeController() {
        withObservationTracking {
            _ = controller.holds
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.refresh()
                self?.observeController()
            }
        }
    }

    /// The readout changes once a minute, and only while a deadline exists (spec §3: no per-second background work).
    private func updateMinuteTimer(needed: Bool) {
        if needed, minuteTimer == nil {
            let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            timer.tolerance = 5
            RunLoop.main.add(timer, forMode: .common)
            minuteTimer = timer
        } else if !needed {
            minuteTimer?.invalidate()
            minuteTimer = nil
        }
    }

    // MARK: Clicks

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showQuickMenu()
        } else {
            togglePopover(sender)
        }
    }

    private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else if let makePopoverContent {
            let hosting = NSHostingController(rootView: makePopoverContent())
            hosting.sizingOptions = .preferredContentSize
            popover.contentViewController = hosting
            popover.delegate = self
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            NSApp.activate()
            popover.contentViewController?.view.window?.makeKey()
        } else {
            showQuickMenu()
        }
    }

    private func showQuickMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(menuItem("Keep Awake for 1 Hour", #selector(startOneHour)))
        menu.addItem(menuItem("Keep Awake Indefinitely", #selector(startIndefinitely)))
        let stop = menuItem("Stop Keeping Awake", #selector(stopAll))
        stop.isEnabled = controller.isAwake
        menu.addItem(stop)
        menu.addItem(menuItem("Open Dashboard…", #selector(openDashboard)))
        menu.addItem(menuItem(onIsHUDPinned?() == true ? "Unpin HUD" : "Pin HUD", #selector(toggleHUD)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit EyesUpGuardian", #selector(quit), key: "q"))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func menuItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func startOneHour() { _ = try? controller.startTimer(duration: 3600, policy: controller.currentPolicy) }
    @objc private func startIndefinitely() { controller.startIndefinite(policy: controller.currentPolicy) }
    @objc private func stopAll() { controller.stopAll() }
    @objc private func openDashboard() { onOpenDashboard?() }
    @objc private func toggleHUD() { onToggleHUD?() }
    @objc private func quit() { NSApp.terminate(nil) }
}

extension StatusItemController: NSPopoverDelegate {
    /// Releases the SwiftUI view so nothing observes the metrics while the popover is closed.
    func popoverDidClose(_ notification: Notification) {
        popover.contentViewController = nil
    }
}
