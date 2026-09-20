import EyesUpCore
import SwiftUI

struct TriggerEditorSheet: View {
    let environment: AppEnvironment
    @Bindable var state: DashboardState
    @Bindable var draft: TriggerDraft

    private let weekdayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(draft.isNew ? "New trigger" : "Edit trigger").font(.title3.bold())

            Form {
                Picker("Keep awake", selection: $draft.kind) {
                    ForEach(TriggerDraft.Kind.allCases) { kind in Text(kind.title).tag(kind) }
                }

                TextField("Name", text: $draft.name, prompt: Text(draft.defaultName))

                conditionFields

                Section {
                    Toggle("Keep the display on too", isOn: $draft.keepDisplayOn)
                    Toggle("Notify me when it starts and stops", isOn: $draft.notifyOnChange)
                    LabeledContent("Stay awake after it ends") {
                        Stepper("\(Int(draft.graceMinutes)) min", value: $draft.graceMinutes, in: 0...120, step: 1)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { state.editingDraft = nil }
                Button(draft.isNew ? "Add trigger" : "Save") { save() }
                    .buttonStyle(.glassProminent)
                    .tint(.orange)
                    .disabled(draft.makeTrigger() == nil)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    @ViewBuilder
    private var conditionFields: some View {
        switch draft.kind {
        case .appRunning:
            Section("Apps") {
                ForEach(environment.workspace.runningApps(), id: \.bundleID) { app in
                    Toggle(app.name, isOn: Binding(
                        get: { draft.bundleIDs.contains(app.bundleID) },
                        set: { isOn in
                            if isOn { draft.bundleIDs.append(app.bundleID) }
                            else { draft.bundleIDs.removeAll { $0 == app.bundleID } }
                        }
                    ))
                }
                if draft.bundleIDs.isEmpty {
                    Text("Pick at least one app.").font(.caption).foregroundStyle(.secondary)
                }
            }
        case .processRunning:
            Section("Command names") {
                TextField("node, claude, swift-build", text: $draft.processNames)
                Text("Separate names with commas. Only processes you own are visible, so commands run with sudo can't be matched.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .schedule:
            Section("Days and times") {
                HStack {
                    ForEach(1...7, id: \.self) { day in
                        Toggle(weekdayNames[day - 1], isOn: Binding(
                            get: { draft.weekdays.contains(day) },
                            set: { isOn in
                                if isOn { draft.weekdays.insert(day) } else { draft.weekdays.remove(day) }
                            }
                        ))
                        .toggleStyle(.button)
                    }
                }
                Stepper("From \(Schedule.time(draft.startMinute))", value: $draft.startMinute, in: 0...1439, step: 15)
                Stepper("To \(Schedule.time(draft.endMinute))", value: $draft.endMinute, in: 0...1439, step: 15)
                Text("An end time earlier than the start means the window runs past midnight.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .cpuBusy:
            Section("Busy means") {
                LabeledContent("CPU above") {
                    Slider(value: $draft.cpuPercent, in: 5...95, step: 5) { Text("CPU") }
                        .frame(width: 200)
                    Text("\(Int(draft.cpuPercent))%").monospacedDigit()
                }
                busyTimings
            }
        case .networkBusy, .diskBusy:
            Section("Busy means") {
                LabeledContent(draft.kind == .networkBusy ? "Traffic above" : "Writes above") {
                    Stepper("\(draft.megabytesPerSecond, format: .number.precision(.fractionLength(1))) MB/s",
                            value: $draft.megabytesPerSecond, in: 0.1...500, step: 0.5)
                }
                busyTimings
            }
        case .displayConnected:
            Section("Display") {
                Picker("Display", selection: Binding(
                    get: { draft.display?.serial },
                    set: { serial in
                        draft.display = LiveDisplayInventory().connectedDisplays().first { $0.serial == serial }
                    }
                )) {
                    Text("Choose…").tag(UInt32?.none)
                    ForEach(LiveDisplayInventory().connectedDisplays(), id: \.serial) { display in
                        Text(display.name).tag(UInt32?.some(display.serial))
                    }
                }
            }
        case .onACPower:
            Text("Useful on a laptop: your Mac stays awake whenever it's plugged in.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var busyTimings: some View {
        Group {
            Stepper("Busy for at least \(Int(draft.sustainMinutes)) min", value: $draft.sustainMinutes, in: 0...60, step: 1)
            Stepper("Quiet for \(Int(draft.releaseMinutes)) min before releasing", value: $draft.releaseMinutes, in: 0...60, step: 1)
        }
    }

    private func save() {
        guard let trigger = draft.makeTrigger() else { return }
        do {
            if draft.isNew {
                try environment.engine.add(trigger)
            } else {
                try environment.engine.update(trigger)
            }
            state.errorMessage = nil
            state.editingDraft = nil
        } catch {
            state.errorMessage = TriggerError.invalid.message
        }
    }
}
