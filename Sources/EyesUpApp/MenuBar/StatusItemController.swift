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

    func setPopoverContent<Content: View>(_ view: Content) {
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting
    }

    func refresh() {
        guard let button = statusItem.button else { return }
        let now = Date()
        let until = controller.awakeUntil
        var fraction: Double?
        if let until, let start = controller.sessionStart {
            fraction = TimeFormatting.remainingFraction(now: now, start: start, end: until)
        }
        button.image = RingIcon.image(active: controller.isAwake, fraction: fraction)
        button.title = until.map { " " + TimeFormatting.menuBar(remaining: $0.timeIntervalSince(now)) } ?? ""
        button.toolTip = controller.isAwake
            ? "EyesUpGuardian: " + controller.holds.map(\.label).joined(separator: ", ")
            : "EyesUpGuardian: your Mac may sleep"
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
        } else if popover.contentViewController != nil {
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
    @objc private func quit() { NSApp.terminate(nil) }
}
