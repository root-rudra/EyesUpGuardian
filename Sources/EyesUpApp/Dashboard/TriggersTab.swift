import EyesUpCore
import SwiftUI

struct TriggersTab: View {
    let environment: AppEnvironment
    @Bindable var state: DashboardState

    private var engine: TriggerEngine { environment.engine }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                suggestions
                if engine.triggers.isEmpty {
                    Text("No triggers yet. Add one to let your Mac stay awake by itself.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                }
                ForEach(engine.triggers) { trigger in
                    row(for: trigger)
                }
                if let notice = engine.storeNotice {
                    Label(notice, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                }
                if let message = state.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                }
            }
            .padding(20)
        }
        .sheet(item: $state.editingDraft) { draft in
            TriggerEditorSheet(environment: environment, state: state, draft: draft)
        }
    }

    private var header: some View {
        HStack {
            Text("Triggers").font(.title2.bold())
            Spacer()
            pauseMenu
            Menu {
                ForEach(TriggerDraft.Kind.allCases) { kind in
                    Button(kind.title) { state.editingDraft = TriggerDraft(kind: kind) }
                }
            } label: {
                Label("New trigger", systemImage: "plus")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private var pauseMenu: some View {
        Menu {
            Button("Pause for 1 hour") { environment.settings.update { $0.triggerPause = .until(Date().addingTimeInterval(3600)) } }
            Button("Pause for 4 hours") { environment.settings.update { $0.triggerPause = .until(Date().addingTimeInterval(4 * 3600)) } }
            Button("Pause until I resume") { environment.settings.update { $0.triggerPause = .untilResumed } }
            Divider()
            Button("Resume triggers") { environment.settings.update { $0.triggerPause = .none } }
                .disabled(!engine.isPaused)
        } label: {
            Label(engine.isPaused ? "Paused" : "Pause", systemImage: engine.isPaused ? "pause.circle.fill" : "pause.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .tint(engine.isPaused ? .orange : .secondary)
    }

    @ViewBuilder
    private var suggestions: some View {
        let running = environment.workspace.runningBundleIDs()
        let offers = TriggerSuggestions.suggestions(running: running, existing: engine.triggers)
        if !offers.isEmpty && !engine.isPaused {
            ForEach(offers) { offer in
                HStack {
                    Image(systemName: "lightbulb").foregroundStyle(.orange)
                    Text("\(offer.displayName) is running. Keep your Mac awake while it is?")
                    Spacer()
                    Button("Add") { add(suggestion: offer) }
                        .buttonStyle(.glassProminent)
                        .tint(.orange)
                }
                .padding(10)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func row(for trigger: Trigger) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(trigger.name).font(.headline)
                Text(trigger.summary).font(.callout).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    if trigger.policy.contains(.display) { Label("Display on", systemImage: "sun.max").font(.caption2) }
                    if trigger.grace > 0 { Label("+\(TimeFormatting.duration(trigger.grace)) after", systemImage: "hourglass").font(.caption2) }
                    if trigger.notifyOnChange { Label("Notifies", systemImage: "bell").font(.caption2) }
                    if environment.controller.hasTriggerHold(triggerID: trigger.id) {
                        Label("Active now", systemImage: "bolt.fill").font(.caption2).foregroundStyle(.orange)
                    }
                }
                .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { trigger.isEnabled },
                set: { engine.setEnabled($0, id: trigger.id) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .tint(.orange)
            Button {
                state.editingDraft = TriggerDraft(trigger: trigger)
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Edit \(trigger.name)")
            Button {
                engine.remove(id: trigger.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Delete \(trigger.name)")
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        .opacity(trigger.isEnabled ? 1 : 0.55)
    }

    private func add(suggestion: TriggerSuggestion) {
        let draft = TriggerDraft(kind: .appRunning)
        draft.bundleIDs = [suggestion.bundleID]
        draft.name = "\(suggestion.displayName) is open"
        guard let trigger = draft.makeTrigger() else { return }
        do {
            try engine.add(trigger)
            state.errorMessage = nil
        } catch {
            state.errorMessage = TriggerError.invalid.message
        }
    }
}
