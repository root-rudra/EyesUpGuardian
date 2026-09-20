import AppKit
import UniformTypeIdentifiers
import EyesUpCore
import SwiftUI

struct SettingsTab: View {
    let environment: AppEnvironment

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

                    Section("Energy") {
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
                            Button("Clear history", role: .destructive) { environment.history.clear() }
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
            try environment.settings.importSettings(Data(contentsOf: url)) // security-allow: a file the user picked in an open panel
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
