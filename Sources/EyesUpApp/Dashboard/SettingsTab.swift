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

    private var pauseDescription: String {
        switch settings.triggerPause {
        case .none: "Running"
        case .untilResumed: "Paused until you resume them"
        case .until(let date): "Paused until " + date.formatted(date: .omitted, time: .shortened)
        }
    }
}
