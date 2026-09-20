import AppKit
import EyesUpCore
import SwiftUI

struct PopoverView: View {
    let controller: AwakeController
    let onOpenDashboard: () -> Void

    /// Owned by the caller (the popover's root is created once), so it persists without `@State`,
    /// whose macro plugin ships only with full Xcode, not the Command Line Tools.
    @Bindable var form: PopoverFormState
    let stats: StatsViewModel
    let environmentSettings: AppSettings
    /// Lets the popover pin the HUD without knowing about windows.
    struct HUDToggle {
        var isPinned: () -> Bool
        var toggle: () -> Void
    }

    let onHUDToggle: HUDToggle

    private var mood: AmbientBackground.Mood { controller.isAwake ? .awake : .idle }
    private var newPolicy: SleepPolicy {
        form.displayForNew || controller.displayOn || environmentSettings.keepDisplayOnByDefault ? [.system, .display] : .system
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            presets
            entryPanel
            if controller.isAwake { activeHolds }
            statTiles
            otherAppsWarning
            messages
            footer
        }
        .padding(18)
        .frame(width: 320)
        .background(AmbientBackground(mood: mood))
        .onAppear { stats.start() }
        .onDisappear { stats.stop() }
    }

    // MARK: Header: live countdown (TimelineView ticks only while the popover is on screen)

    private var header: some View {
        HStack(alignment: .top) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline).font(.callout).foregroundStyle(.secondary)
                    Text(bigText(now: context.date))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .shadow(color: AmbientBackground(mood: mood).primary.opacity(0.6), radius: 12)
                    if controller.isAwake {
                        Text(controller.holds.map(\.label).joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }
            Spacer()
            Toggle("Keep awake", isOn: Binding(
                get: { controller.isAwake },
                set: { on in
                    if on { controller.startIndefinite(policy: newPolicy) } else { controller.stopAll() }
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .tint(.orange)
        }
    }

    private var headline: String {
        guard controller.isAwake else { return "Your Mac may sleep" }
        return controller.awakeUntil == nil ? "Awake" : "Awake for another"
    }

    private func bigText(now: Date) -> String {
        guard controller.isAwake else { return "Idle" }
        guard let until = controller.awakeUntil else { return "No end time" }
        return TimeFormatting.countdown(until.timeIntervalSince(now))
    }

    // MARK: Presets and entry

    private var presets: some View {
        VStack(alignment: .leading, spacing: 8) {
            GlassEffectContainer {
                HStack(spacing: 6) {
                    ForEach(environmentSettings.presets, id: \.self) { seconds in
                        Button(TimeFormatting.duration(seconds)) {
                            run { try controller.startTimer(duration: seconds, policy: newPolicy) }
                        }
                        .buttonStyle(.glass)
                    }
                    Button("∞") { run { controller.startIndefinite(policy: newPolicy) } }
                        .buttonStyle(.glass)
                        .accessibilityLabel("Keep awake indefinitely")
                }
            }
            HStack(spacing: 6) {
                entryButton("Until…", .until)
                entryButton("Custom…", .custom)
                entryButton("Process…", .pid)
                Spacer()
                Toggle("Display on", isOn: Binding(
                    get: { controller.isAwake ? controller.displayOn : form.displayForNew },
                    set: { on in
                        form.displayForNew = on
                        if controller.isAwake { controller.setDisplayOn(on) }
                    }
                ))
                .toggleStyle(.button)
                .help("Keep the display on too (caffeinate -d)")
            }
            .controlSize(.small)
        }
    }

    private func entryButton(_ title: String, _ target: PopoverFormState.Entry) -> some View {
        Button(title) { form.select(target, now: Date()) }
        .buttonStyle(.glass)
    }

    @ViewBuilder
    private var entryPanel: some View {
        switch form.entry {
        case .none:
            EmptyView()
        case .until:
            HStack {
                DatePicker("Until", selection: $form.untilDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                Button("Start") { run { try controller.startUntil(form.untilDate, policy: newPolicy) } }
                    .buttonStyle(.glassProminent).tint(.orange)
            }
        case .custom:
            HStack {
                TextField("45m, 2h or 1h30m", text: $form.customText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(startCustom)
                Button("Start", action: startCustom).buttonStyle(.glassProminent).tint(.orange)
            }
        case .pid:
            HStack {
                TextField("Process ID, e.g. 48213", text: $form.pidText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(startPID)
                Button("Watch", action: startPID).buttonStyle(.glassProminent).tint(.orange)
            }
        }
    }

    private func startCustom() {
        run {
            switch DurationParser.parse(form.customText) {
            case .finite(let seconds): try controller.startTimer(duration: seconds, policy: newPolicy)
            case .infinite: controller.startIndefinite(policy: newPolicy)
            case nil: throw AwakeError.invalidDuration
            }
            form.customText = ""
        }
    }

    private func startPID() {
        run {
            try controller.watchProcess(pid: AwakeController.parsePID(form.pidText), policy: newPolicy)
            form.pidText = ""
        }
    }

    // MARK: Active holds

    private var activeHolds: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(controller.holds) { hold in
                HStack {
                    Image(systemName: icon(for: hold)).foregroundStyle(.orange)
                    Text(hold.label).lineLimit(1)
                    Spacer()
                    Button {
                        controller.stop(id: hold.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Stop \(hold.label)")
                }
                .font(.callout)
            }
            HStack(spacing: 6) {
                if controller.awakeUntil != nil {
                    Button("+30m") { run { try controller.extend(by: Defaults.extendStep, policy: controller.currentPolicy) } }
                        .buttonStyle(.glass)
                }
                Button {
                    controller.nudgeDisplay()
                } label: {
                    Label("Wake display", systemImage: "sun.max")
                }
                .buttonStyle(.glass)
                .help("Wake the display now (caffeinate -u)")
                Spacer()
                Button("Stop all") { controller.stopAll() }
                    .buttonStyle(.glass)
            }
            .controlSize(.small)
        }
    }

    private func icon(for hold: Hold) -> String {
        switch hold.end {
        case .indefinite: "infinity"
        case .deadline: "timer"
        case .processExit: "gearshape"
        case .triggerControlled: "bolt"
        }
    }

    private var statTiles: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
            ForEach(stats.tiles) { tile in
                StatTile(title: tile.title, value: tile.value, detail: tile.detail, symbol: tile.symbol)
            }
        }
    }

    /// Spec §7.2: say when something *else* is the reason the Mac won't sleep.
    @ViewBuilder
    private var otherAppsWarning: some View {
        if let others = stats.snapshot.otherAssertions, !others.isEmpty {
            let names = Set(others.map(\.processName)).sorted().prefix(3).joined(separator: ", ")
            Label("\(names) \(others.count == 1 ? "is" : "are") also keeping your Mac awake",
                  systemImage: "exclamationmark.bubble")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Messages and footer

    @ViewBuilder
    private var messages: some View {
        if let errorMessage = form.errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
        }
        if let error = controller.lastError {
            Label("macOS refused a keep-awake request (code \(error.code)). Retrying on the next change.",
                  systemImage: "exclamationmark.octagon")
                .font(.caption).foregroundStyle(.red)
        }
        if let notice = controller.storeNotice {
            Label(notice, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            Text("EyesUpGuardian").font(.caption2).foregroundStyle(.tertiary)
            Spacer()
            Button(onHUDToggle.isPinned() ? "Unpin HUD" : "Pin HUD") { onHUDToggle.toggle() }
                .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
            Button("Dashboard ↗") { onOpenDashboard() }
                .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func run(_ action: () throws -> Void) {
        do {
            try action()
            form.errorMessage = nil
            form.entry = .none
        } catch let error as AwakeError {
            form.errorMessage = error.message
        } catch {
            form.errorMessage = error.localizedDescription
        }
    }
}

/// The popover's in-progress input. A class so it survives SwiftUI view updates without `@State`.
@MainActor
@Observable
final class PopoverFormState {
    enum Entry { case none, until, custom, pid }

    var entry: Entry = .none
    var untilDate = Date().addingTimeInterval(3600)
    var customText = ""
    var pidText = ""
    var errorMessage: String?
    var displayForNew = false

    /// Opens a panel (or closes it if already open). Opening Until… starts from an hour after *now*,
    /// not from whenever this state was created.
    func select(_ target: Entry, now: Date) {
        entry = entry == target ? .none : target
        errorMessage = nil
        if entry == .until { untilDate = now.addingTimeInterval(3600) }
    }
}
