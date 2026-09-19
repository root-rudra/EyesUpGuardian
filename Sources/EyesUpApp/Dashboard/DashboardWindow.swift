import AppKit
import EyesUpCore
import SwiftUI

/// Which tab is showing and which sheet is open. A class because `@State` is unavailable
/// with the Command Line Tools (see the plan's Global Constraints).
@MainActor
@Observable
final class DashboardState {
    enum Tab: String, CaseIterable, Identifiable, Hashable {
        case triggers, settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .triggers: "Triggers"
            case .settings: "Settings"
            }
        }

        var symbol: String {
            switch self {
            case .triggers: "bolt.badge.clock"
            case .settings: "gearshape"
            }
        }
    }

    var tab: Tab = .triggers
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
                case .triggers: TriggersTab(environment: environment, state: state)
                case .settings: SettingsTab(environment: environment)
                }
            }
        }
        .frame(minWidth: 700, minHeight: 460)
    }
}

// Replaced in Task 14.
struct TriggersTab: View {
    let environment: AppEnvironment
    @Bindable var state: DashboardState
    var body: some View { Text("Triggers").padding() }
}

// Replaced in Task 15.
struct SettingsTab: View {
    let environment: AppEnvironment
    var body: some View { Text("Settings").padding() }
}

// Replaced in Task 14.
@MainActor
@Observable
final class TriggerDraft: Identifiable {
    let id = UUID()
}
