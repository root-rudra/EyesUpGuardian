import AppKit
import EyesUpCore
import SwiftUI

/// Which tab is showing and which sheet is open. A class because `@State` is unavailable
/// with the Command Line Tools (see the plan's Global Constraints).
@MainActor
@Observable
final class DashboardState {
    enum Tab: String, CaseIterable, Identifiable, Hashable {
        case overview, triggers, processes, settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .overview: "Overview"
            case .triggers: "Triggers"
            case .processes: "Processes"
            case .settings: "Settings"
            }
        }

        var symbol: String {
            switch self {
            case .overview: "gauge.with.dots.needle.50percent"
            case .triggers: "bolt.badge.clock"
            case .processes: "list.bullet.rectangle"
            case .settings: "gearshape"
            }
        }
    }

    var tab: Tab = .overview
    /// Kept for the window's lifetime so switching tabs doesn't restart sampling from scratch.
    var overviewStats: StatsViewModel?
    var processesStats: StatsViewModel?
    let processes = ProcessesState()
    var editingDraft: TriggerDraft?
    var errorMessage: String?
}

/// Owns the single dashboard window. Reused if it's already open.
@MainActor
final class DashboardWindowController {
    private let environment: AppEnvironment
    private let state = DashboardState()
    private var window: NSWindow?

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        if state.overviewStats == nil {
            state.overviewStats = StatsViewModel(
                center: environment.metrics,
                ids: [.cpu, .memory, .system, .storage, .network, .power, .fans, .temperature, .gpu, .otherAssertions],
                interval: 1
            )
        }
        if state.processesStats == nil {
            state.processesStats = StatsViewModel(center: environment.metrics, ids: [.processes, .system], interval: 2)
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "EyesUpGuardian"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: DashboardView(environment: environment, state: state))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        self.window = window
    }
}

struct DashboardView: View {
    let environment: AppEnvironment
    @Bindable var state: DashboardState

    var body: some View {
        NavigationSplitView {
            List(DashboardState.Tab.allCases, selection: $state.tab) { tab in
                Label(tab.title, systemImage: tab.symbol).tag(tab)
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 180, max: 240)
        } detail: {
            ZStack {
                AmbientBackground(mood: environment.controller.isAwake ? .awake : .idle)
                switch state.tab {
                case .overview:
                    if let stats = state.overviewStats { OverviewTab(environment: environment, stats: stats) }
                case .triggers: TriggersTab(environment: environment, state: state)
                case .processes:
                    if let stats = state.processesStats {
                        ProcessesTab(environment: environment, stats: stats, state: state.processes)
                    }
                case .settings: SettingsTab(environment: environment)
                }
            }
        }
        .frame(minWidth: 700, minHeight: 460)
    }
}
