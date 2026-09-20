import AppKit
import UniformTypeIdentifiers
import EyesUpCore
import Observation
import SwiftUI

/// Held by the dashboard, because this project builds without Xcode and SwiftUI's `@State` macro
/// ships only with it.
@MainActor
@Observable
final class SettingsTabState {
    var confirmingClearHistory = false
    var confirmingReset = false
}

struct SettingsTab: View {
    let environment: AppEnvironment
    @Bindable var state: SettingsTabState

    private var settings: AppSettings { environment.settings.settings }

    /// Off, plus the caps offered in the picker.
    private let capChoices: [Double?] = [nil, 1, 2, 4, 8, 12, 24, 48]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Settings").font(.title2.bold())

                Form {
                    Section("Menu bar") {
                        Picker("Show", selection: Binding(
                            get: { settings.menuBarReadout },
                            set: { readout in environment.settings.update { $0.menuBarReadout = readout } }
                        )) {
                            ForEach(MenuBarReadout.allCases, id: \.self) { readout in
                                Text(readout.title).tag(readout)
                            }
                        }
                        Toggle("Count down every second", isOn: Binding(
                            get: { settings.menuBarTicksEverySecond },
                            set: { on in environment.settings.update { $0.menuBarTicksEverySecond = on } }
                        ))
                        Text("On, the time reads like a clock (12:45). Off, it shows whole minutes (13m) and the menu bar redraws once a minute instead of once a second. Either way nothing ticks while no session is running.")
                            .font(.caption).foregroundStyle(.secondary)
                                                Text("Stats in the menu bar refresh every 2 seconds. With \"Icon only\" or \"Icon and time left\", nothing is measured at all.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    Section("Safety") {
                        Picker("Never stay awake longer than", selection: Binding(
                            get: { settings.safetyCapHours },
                            set: { hours in environment.settings.update { $0.safetyCapHours = hours } }
                        )) {
                            ForEach(capChoices, id: \.self) { choice in
                                Text(choice.map { "\(Int($0)) hours" } ?? "No limit").tag(choice)
                            }
                        }
                        Toggle("Let my Mac sleep if it gets too hot", isOn: Binding(
                            get: { settings.thermalAutoRelease },
                            set: { on in environment.settings.update { $0.thermalAutoRelease = on } }
                        ))
                        Text("Both apply to every keep-awake session, including triggers.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    Section("Automation link") {
                        Toggle("Allow eyesup:// links", isOn: Binding(
                            get: { settings.automationEnabled },
                            set: { on in environment.settings.update { $0.automationEnabled = on } }
                        ))
                        Text("""
                        Off by default. When on, scripts can run:
                          open "eyesup://start?for=2h"
                          open "eyesup://start?for=90m&display=true"
                          open "eyesup://extend?by=30m"
                          open "eyesup://stop"
                        Links can only start, extend or stop their own session, never longer than 24 hours, \
                        and never anything else. They can't touch sessions you started yourself.
                        """)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    }

                    Section("Keep awake") {
                        Toggle("Open EyesUpGuardian at login", isOn: Binding(
                            get: { environment.launchAtLogin.isEnabled },
                            set: { on in
                                if let message = environment.launchAtLogin.set(on) {
                                    environment.settings.reportNotice(message)
                                } else {
                                    environment.settings.update { $0.launchAtLogin = on }
                                }
                            }
                        ))
                        Toggle("Keep the display on by default", isOn: Binding(
                            get: { settings.keepDisplayOnByDefault },
                            set: { on in environment.settings.update { $0.keepDisplayOnByDefault = on } }
                        ))
                        LabeledContent("Warn me before sleep") {
                            Stepper("\(Int(settings.headsUpLeadMinutes)) min", value: Binding(
                                get: { settings.headsUpLeadMinutes },
                                set: { value in environment.settings.update { $0.headsUpLeadMinutes = value } }
                            ), in: AppSettings.minHeadsUpLeadMinutes...AppSettings.maxHeadsUpLeadMinutes, step: 1)
                        }
                        LabeledContent("Quick presets") {
                            Text(settings.presets.map { TimeFormatting.duration($0) }.joined(separator: " · "))
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            ForEach([300.0, 900, 1800, 3600, 7200, 14400, 28800], id: \.self) { seconds in
                                Toggle(TimeFormatting.duration(seconds), isOn: Binding(
                                    get: { settings.presets.contains(seconds) },
                                    set: { on in
                                        environment.settings.update { current in
                                            var presets = Set(current.presets)
                                            if on { presets.insert(seconds) } else { presets.remove(seconds) }
                                            current.presets = presets.sorted()
                                        }
                                    }
                                ))
                                .toggleStyle(.button)
                                .controlSize(.small)
                            }
                        }
                    }

                    Section("Floating HUD") {
                        Toggle("Show the HUD", isOn: Binding(
                            get: { settings.hudVisible },
                            set: { on in environment.onToggleHUD?(on) }
                        ))
                        Toggle("Let clicks pass through it", isOn: Binding(
                            get: { settings.hudClickThrough },
                            set: { on in environment.settings.update { $0.hudClickThrough = on } }
                        ))
                        Text("The HUD floats above other apps and snaps to the nearest corner when you drag it.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    Section("Shortcut") {
                        Toggle("Global shortcut (\(GlobalShortcut.description))", isOn: Binding(
                            get: { settings.globalShortcutEnabled },
                            set: { on in environment.settings.update { $0.globalShortcutEnabled = on } }
                        ))
                        Text("Turns keeping awake on or off from anywhere. It needs no accessibility permission — this app never reads your keystrokes.")
                            .font(.caption).foregroundStyle(.secondary)
                        if let error = environment.shortcut.lastError {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }

                    Section("Process list") {
                        Picker("Font", selection: Binding(
                            get: { settings.processFont },
                            set: { font in environment.settings.update { $0.processFont = font } }
                        )) {
                            ForEach(TableFont.allCases, id: \.self) { font in Text(font.title).tag(font) }
                        }
                        Picker("Size", selection: Binding(
                            get: { settings.processFontSize },
                            set: { size in environment.settings.update { $0.processFontSize = size } }
                        )) {
                            ForEach(AppSettings.processFontSizes, id: \.self) { size in
                                Text("\(Int(size)) pt").tag(size)
                            }
                        }
                        Text("Used by the table on the Processes tab. Numbers always line up, whichever font you pick.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    Section("Sleep types") {
                        Toggle("Also keep the disk awake (caffeinate -m)", isOn: Binding(
                            get: { settings.keepDiskAwake },
                            set: { on in environment.settings.update { $0.keepDiskAwake = on } }
                        ))
                        Toggle("Only prevent sleep while on AC power (caffeinate -s)", isOn: Binding(
                            get: { settings.onlyOnACPower },
                            set: { on in environment.settings.update { $0.onlyOnACPower = on } }
                        ))
                        Text("Added to every session you start from the app. Triggers keep the sleep types you gave them, and automation links stay on the plain system hold.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    Section("Energy") {
                        Toggle("Track energy", isOn: Binding(
                            get: { settings.trackEnergy },
                            set: { on in environment.settings.update { $0.trackEnergy = on } }
                        ))
                        Text("Reads power draw every 30 seconds so the History tab can show energy and cost. It is the only thing this app measures when nothing is on screen; turn it off and it measures nothing at all.")
                            .font(.caption).foregroundStyle(.secondary)
                        LabeledContent("Electricity rate") {
                            TextField("none", value: Binding(
                                get: { settings.electricityRate },
                                set: { rate in environment.settings.update { $0.electricityRate = rate } }
                            ), format: .number.precision(.fractionLength(0...3)))
                            .frame(width: 90)
                            Text("per kWh").foregroundStyle(.secondary)
                        }
                        Text("Used only to turn the energy the Mac drew into money on the History tab. Leave it empty and the app shows kilowatt-hours only.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    Section("Your data") {
                        HStack {
                            Button("Export settings…") { exportSettings() }
                            Button("Import settings…") { importSettings() }
                            Spacer()
                            Button("Clear history", role: .destructive) { state.confirmingClearHistory = true }
                                .confirmationDialog(
                                    "Clear all history?",
                                    isPresented: Binding(get: { state.confirmingClearHistory },
                                                         set: { state.confirmingClearHistory = $0 })
                                ) {
                                    Button("Clear history", role: .destructive) {
                                        environment.history.clear()
                                        state.confirmingClearHistory = false
                                    }
                                    Button("Cancel", role: .cancel) { state.confirmingClearHistory = false }
                                } message: {
                                    Text("Every session, sleep/wake event and energy day is deleted. This can't be undone.")
                                }
                        }
                        Button("Reset settings to defaults", role: .destructive) { state.confirmingReset = true }
                            .confirmationDialog(
                                "Reset every setting?",
                                isPresented: Binding(get: { state.confirmingReset },
                                                     set: { state.confirmingReset = $0 })
                            ) {
                                Button("Reset settings", role: .destructive) {
                                    environment.settings.resetToDefaults()
                                    state.confirmingReset = false
                                }
                                Button("Cancel", role: .cancel) { state.confirmingReset = false }
                            } message: {
                                Text("Your triggers, sessions and history are kept. Only the settings on this tab go back to their defaults.")
                            }
                        Text("Everything this app stores lives in ~/Library/Application Support/EyesUpGuardian, readable only by you.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    Section("Triggers") {
                        LabeledContent("Status") {
                            Text(pauseDescription)
                        }
                        Button("Resume triggers") {
                            environment.settings.update { $0.triggerPause = .none }
                        }
                        .disabled(!environment.engine.isPaused)
                    }
                }
                .formStyle(.grouped)

                if let notice = environment.settings.storeNotice {
                    Label(notice, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
    }

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "EyesUpGuardian-settings.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try environment.settings.export().write(to: url, options: .atomic)
        } catch {
            environment.settings.reportNotice("Couldn't export settings: \(error.localizedDescription)")
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            // Capped like the app's own reads: a settings file is a few hundred bytes, and reading
            // an arbitrary multi-gigabyte file into memory is not a thing this app should do.
            let data = try Data(contentsOf: url, options: .alwaysMapped) // security-allow: a file the user picked in an open panel
            guard data.count <= JSONFileStore<AppSettings>.maxFileSize else {
                environment.settings.reportNotice("That file is too large to be a settings file.")
                return
            }
            try environment.settings.importSettings(Data(data))
        } catch {
            environment.settings.reportNotice("That file isn't a settings file this app can read.")
        }
    }

    private var pauseDescription: String {
        switch settings.triggerPause {
        case .none: "Running"
        case .untilResumed: "Paused until you resume them"
        case .until(let date): "Paused until " + date.formatted(date: .omitted, time: .shortened)
        }
    }
}
