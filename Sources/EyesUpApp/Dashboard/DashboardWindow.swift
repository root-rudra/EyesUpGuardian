import AppKit
import EyesUpCore
import SwiftUI

/// Which tab is showing and which sheet is open. A class because `@State` is unavailable
/// with the Command Line Tools (see the plan's Global Constraints).
@MainActor
@Observable
final class DashboardState {
    enum Tab: String, CaseIterable, Identifiable, Hashable {
        case overview, triggers, processes, history, settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .overview: "Overview"
            case .triggers: "Triggers"
            case .processes: "Processes"
            case .history: "History"
            case .settings: "Settings"
            }
        }

        /// ⌘1–⌘5, in sidebar order.
        var shortcut: KeyEquivalent {
            switch self {
            case .overview: "1"
            case .triggers: "2"
            case .processes: "3"
            case .history: "4"
            case .settings: "5"
            }
        }

        var symbol: String {
            switch self {
            case .overview: "gauge.with.dots.needle.50percent"
            case .triggers: "bolt.badge.clock"
            case .processes: "list.bullet.rectangle"
            case .history: "clock.arrow.trianglehead.counterclockwise.rotate.90"
            case .settings: "gearshape"
            }
        }
    }

    var tab: Tab = .overview {
        didSet { onTabChange?(tab) }
    }

    /// Set by the window controller: remembers the tab, so the dashboard reopens where you left it.
    @ObservationIgnored var onTabChange: ((Tab) -> Void)?
    /// Kept for the window's lifetime so switching tabs doesn't restart sampling from scratch.
    var overviewStats: StatsViewModel?
    /// The registry walks and disk sweeps, on a slower cadence than the headline numbers.
    var overviewSlowStats: StatsViewModel?
    var processesStats: StatsViewModel?
    let processes = ProcessesState()
    let history = HistoryTabState()
    let settings = SettingsTabState()
    var editingDraft: TriggerDraft?
    var errorMessage: String?

    /// Every metrics claim this window holds. The window stops these when it is closed, minimised
    /// or fully covered, so a claim that isn't listed here would keep sampling with nothing on
    /// screen — which is exactly what happened when Overview gained its second subscription.
    var sampling: [StatsViewModel] {
        [overviewStats, overviewSlowStats, processesStats].compactMap { $0 }
    }

    /// What the given tab needs while it is on screen.
    func sampling(for tab: Tab) -> [StatsViewModel] {
        switch tab {
        case .overview: [overviewStats, overviewSlowStats].compactMap { $0 }
        case .processes: [processesStats].compactMap { $0 }
        case .triggers, .history, .settings: []
        }
    }
}

/// Owns the single dashboard window. Reused if it's already open.
@MainActor
final class DashboardWindowController: NSObject, NSWindowDelegate {
    private let environment: AppEnvironment
    private let state = DashboardState()
    private var window: NSWindow?

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init()
    }

    func show() {
        if state.onTabChange == nil {
            // Qualified: SwiftUI has its own `Tab` type in scope here.
            state.tab = DashboardState.Tab(rawValue: environment.settings.settings.dashboardTab) ?? state.tab
            state.onTabChange = { [environment] tab in
                guard environment.settings.settings.dashboardTab != tab.rawValue else { return }
                environment.settings.update { $0.dashboardTab = tab.rawValue }
            }
        }
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        if state.overviewStats == nil {
            // Split by what it costs to read: CPU and memory are two cheap syscalls, while the GPU,
            // disk and assertion probes walk the IOKit registry. The tiles all read one merged
            // snapshot, so the slower half simply refreshes less often.
            state.overviewStats = StatsViewModel(
                center: environment.metrics,
                ids: [.cpu, .memory, .system],
                interval: 1
            )
            state.overviewSlowStats = StatsViewModel(
                center: environment.metrics,
                ids: [.storage, .network, .power, .fans, .temperature, .gpu, .otherAssertions],
                interval: 5
            )
        }
        if state.processesStats == nil {
            state.processesStats = StatsViewModel(center: environment.metrics, ids: [.processes, .system],
                                              interval: environment.settings.settings.processRefreshSeconds)
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "EyesUpGuardian"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.contentView = NSHostingView(rootView: DashboardView(environment: environment, state: state))
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        self.window = window
    }
    // Spec §6.1: a window nobody can see must not sample. SwiftUI's onDisappear covers neither
    // miniaturizing nor being fully covered by another window, so the window itself reports both.
    func windowWillClose(_ notification: Notification) { stopSampling() }

    func windowDidMiniaturize(_ notification: Notification) { stopSampling() }

    func windowDidDeminiaturize(_ notification: Notification) { startVisibleTab() }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        guard let window else { return }
        window.occlusionState.contains(.visible) ? startVisibleTab() : stopSampling()
    }

    private func stopSampling() {
        for model in state.sampling { model.stop() }
    }

    private func startVisibleTab() {
        for model in state.sampling(for: state.tab) { model.start() }
    }

}

struct DashboardView: View {
    let environment: AppEnvironment
    @Bindable var state: DashboardState

    var body: some View {
        NavigationSplitView {
            List(DashboardState.Tab.allCases, selection: $state.tab) { tab in
                Label(tab.title, systemImage: tab.symbol)
                    .tag(tab)
                    .keyboardShortcut(tab.shortcut, modifiers: .command)
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 180, max: 240)
        } detail: {
            ZStack {
                AmbientBackground(mood: environment.controller.isAwake ? .awake : .idle)
                switch state.tab {
                case .overview:
                    if let stats = state.overviewStats, let slow = state.overviewSlowStats {
                        OverviewTab(environment: environment, stats: stats, slowStats: slow)
                    }
                case .triggers: TriggersTab(environment: environment, state: state)
                case .processes:
                    if let stats = state.processesStats {
                        ProcessesTab(environment: environment, stats: stats, state: state.processes)
                    }
                case .history: HistoryTab(environment: environment, state: state.history)
                case .settings: SettingsTab(environment: environment, state: state.settings)
                }
            }
        }
        .frame(minWidth: 700, minHeight: 460)
    }
}
