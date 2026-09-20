import AppKit
import EyesUpCore
import SwiftUI

/// Tracked separately from the view so the fade survives a redraw (this project builds without
/// Xcode, so SwiftUI's `@State` macro is unavailable).
@MainActor
@Observable
final class HUDHoverState {
    var isHovering = false
}

/// The pinnable mini panel (spec §7.4): a draining ring, the countdown and a compact stat line, on
/// every Space. It fades when the pointer is elsewhere and snaps to the nearest corner when dragged.
struct HUDView: View {
    let controller: AwakeController
    @Bindable var stats: StatsViewModel
    @Bindable var hover: HUDHoverState

    var body: some View {
        // A per-second tick only earns its keep while a countdown is running: with no deadline the
        // HUD's text changes at most once a minute, and this panel is always on screen.
        Group {
            if controller.awakeUntil != nil {
                TimelineView(.periodic(from: .now, by: 1)) { context in panel(now: context.date) }
            } else {
                TimelineView(.everyMinute) { context in panel(now: context.date) }
            }
        }
        .background(AmbientBackground(mood: controller.isAwake ? .awake : .idle))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .opacity(hover.isHovering ? 1 : 0.4)
        .animation(.easeInOut(duration: 0.2), value: hover.isHovering)
        .onHover { hover.isHovering = $0 }
        .onAppear { stats.start() }
        .onDisappear { stats.stop() }
    }

    private func panel(now: Date) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: RingIcon.image(active: controller.isAwake, fraction: ringFraction(now: now)))
                .renderingMode(.template)
                .foregroundStyle(controller.isAwake ? .orange : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(countdown(now: now))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(statLine).font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func ringFraction(now: Date) -> Double? {
        guard let until = controller.awakeUntil, let start = controller.sessionStart else { return nil }
        return TimeFormatting.remainingFraction(now: now, start: start, end: until)
    }

    private func countdown(now: Date) -> String {
        guard controller.isAwake else { return "Idle" }
        guard let until = controller.awakeUntil else { return "No end time" }
        return TimeFormatting.countdown(until.timeIntervalSince(now))
    }

    private var statLine: String {
        let snapshot = stats.snapshot
        var parts = ["CPU " + StatFormatting.percent(snapshot.cpu?.total)]
        if let memory = snapshot.memory { parts.append("RAM " + StatFormatting.bytes(memory.usedBytes)) }
        if let power = snapshot.power { parts.append(StatFormatting.watts(power.watts)) }
        if let temperature = snapshot.temperature { parts.append(StatFormatting.celsius(temperature.celsius)) }
        return parts.joined(separator: " · ")
    }
}

/// A borderless panel that floats above other windows without stealing focus.
@MainActor
final class HUDWindowController {
    private let environment: AppEnvironment
    private var panel: NSPanel?
    private var stats: StatsViewModel?
    private let hover = HUDHoverState()
    private var moveObserver: NSObjectProtocol?
    private var settleTimer: Timer?

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        if let panel {
            panel.orderFrontRegardless()
            return
        }
        let model = StatsViewModel(center: environment.metrics, ids: [.cpu, .memory, .power, .temperature], interval: 1)
        stats = model
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 230, height: 56),
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: HUDView(controller: environment.controller, stats: model, hover: hover))
        self.panel = panel
        place(panel)
        // A saved position from another display arrangement could leave it half off an edge.
        snapToNearestCorner()
        panel.ignoresMouseEvents = environment.settings.settings.hudClickThrough
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleSnap() }
        }
        panel.orderFrontRegardless()
        environment.settings.update { $0.hudVisible = true }
    }

    func hide() {
        savePosition()
        if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
        moveObserver = nil
        settleTimer?.invalidate()
        settleTimer = nil
        stats?.stop()
        stats = nil
        panel?.orderOut(nil)
        panel = nil
        environment.settings.update { $0.hudVisible = false }
    }

    /// Remembers where it was dragged to, so it comes back in the same corner.
    func savePosition() {
        guard let panel else { return }
        let origin = panel.frame.origin
        environment.settings.update { $0.hudPosition = HUDPosition(x: Double(origin.x), y: Double(origin.y)) }
    }

    /// `didMove` fires all through a drag, so the snap waits until the panel has been still for a
    /// moment — the effect of letting go, without watching the mouse. The timer lives only while
    /// the panel is actually moving.
    private func scheduleSnap() {
        settleTimer?.invalidate()
        settleTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.snapToNearestCorner() }
        }
    }

    /// Called when the panel stops moving: it always ends up in a corner, never half off an edge.
    func snapToNearestCorner() {
        settleTimer?.invalidate()
        settleTimer = nil
        guard let panel, let screen = panel.screen ?? NSScreen.main else { return }
        let current = HUDPosition(x: Double(panel.frame.origin.x), y: Double(panel.frame.origin.y))
        let snapped = current.snapped(in: screen.visibleFrame, size: panel.frame.size, margin: 20)
        guard snapped != current else { return }
        panel.setFrameOrigin(NSPoint(x: snapped.x, y: snapped.y))
        environment.settings.update { $0.hudPosition = snapped }
    }

    func applyClickThrough(_ enabled: Bool) {
        panel?.ignoresMouseEvents = enabled
    }

    private func place(_ panel: NSPanel) {
        if let saved = environment.settings.settings.hudPosition,
           let screen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: saved.x, y: saved.y)) }) ?? NSScreen.main,
           screen.frame.contains(NSPoint(x: saved.x, y: saved.y)) {
            panel.setFrameOrigin(NSPoint(x: saved.x, y: saved.y))
        } else if let screen = NSScreen.main {
            // Default: top-right, below the menu bar.
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.maxX - panel.frame.width - 20, y: frame.maxY - panel.frame.height - 20))
        }
    }
}
