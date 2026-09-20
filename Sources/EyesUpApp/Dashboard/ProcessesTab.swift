import AppKit
import EyesUpCore
import SwiftUI

/// Which processes the table is showing. "All" groups them; a single origin lists them flat.
enum ProcessScope: String, CaseIterable, Identifiable {
    case all, macOS, installed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .macOS: "macOS"
        case .installed: "Installed"
        }
    }

    var origin: ProcessOrigin? {
        switch self {
        case .all: nil
        case .macOS: .macOS
        case .installed: .installed
        }
    }
}

/// One group of rows under its own header.
struct ProcessGroup: Identifiable {
    let origin: ProcessOrigin
    let entries: [ProcessEntry]
    var id: String { origin.rawValue }
}

@MainActor
@Observable
final class ProcessesState {
    var filter = ""
    var scope: ProcessScope = .all
    var sortOrder = [KeyPathComparator(\ProcessEntry.cpuPercent, order: .reverse)]
    var selection: ProcessEntry.ID?
    /// Right-click the table's header to show or hide columns, as macOS tables do.
    var columns = TableColumnCustomization<ProcessEntry>()
    var confirmingQuit: ProcessEntry?
    var forceQuit = false
    var message: String?
}

extension ProcessEntry {
    /// A sortable owner column: "You" before "System" when sorted ascending.
    var ownerLabel: String { isOwn ? "You" : "System" }
}

/// The process table (spec §7.3), laid out the way macOS lays out a list of things: a native table
/// with sortable column headers, the real app icons, and rows grouped by where the process came from.
struct ProcessesTab: View {
    let environment: AppEnvironment
    @Bindable var stats: StatsViewModel
    @Bindable var state: ProcessesState

    private var settings: AppSettings { environment.settings.settings }

    private var rowFont: Font {
        let size = settings.processFontSize
        return switch settings.processFont {
        case .system: .system(size: size)
        case .rounded: .system(size: size, design: .rounded)
        case .monospaced: .system(size: size, design: .monospaced)
        }
    }

    private var entries: [ProcessEntry] {
        ProcessTableModel.rows(from: stats.snapshot.processes ?? [], scope: state.scope,
                               filter: state.filter, sortOrder: state.sortOrder)
    }

    private var groups: [ProcessGroup] { ProcessTableModel.groups(of: entries) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            table
            if let message = state.message { notice(message) }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear {
            stats.setInterval(settings.processRefreshSeconds)
            stats.start()
        }
        .onDisappear {
            stats.stop()
            ProcessIcons.forget()
        }
        .confirmationDialog(
            state.confirmingQuit.map { "\(state.forceQuit ? "Force quit" : "Quit") \($0.name) (PID \($0.pid))?" } ?? "",
            isPresented: Binding(get: { state.confirmingQuit != nil }, set: { if !$0 { state.confirmingQuit = nil } }),
            titleVisibility: .visible
        ) {
            Button(state.forceQuit ? "Force Quit" : "Quit", role: .destructive) { confirmQuit() }
            Button("Cancel", role: .cancel) { state.confirmingQuit = nil }
        } message: {
            Text(state.forceQuit
                 ? "The process is ended immediately and unsaved work is lost."
                 : "The process is asked to quit.")
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Processes").font(.title3.bold())
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
            }
            HStack(spacing: 10) {
                Picker("Show", selection: $state.scope) {
                    ForEach(ProcessScope.allCases) { scope in Text(scope.title).tag(scope) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
                refreshPicker
                searchField
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    /// Activity Monitor keeps this in its View menu; here it sits with the table it governs, because
    /// it is the one control that decides what this tab costs while it is open.
    private var refreshPicker: some View {
        Picker("Update", selection: Binding(
            get: { settings.processRefreshSeconds },
            set: { seconds in
                environment.settings.update { $0.processRefreshSeconds = seconds }
                stats.setInterval(seconds)
            }
        )) {
            ForEach(AppSettings.processRefreshChoices, id: \.self) { seconds in
                Text("\(Int(seconds))s").tag(seconds)
            }
        }
        .pickerStyle(.menu)
        .fixedSize()
        .help("How often this table re-reads the process list. 5 seconds is what Activity Monitor uses; 1 second costs about four times as much CPU.")
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search", text: $state.filter)
                .textFieldStyle(.plain)
            if !state.filter.isEmpty {
                Button {
                    state.filter = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear the search")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
        .frame(width: 220)
    }

    private var summary: String {
        let shown = entries
        let threads = shown.reduce(0) { $0 + $1.threads }
        let load = stats.snapshot.system?.loadAverage
        let loadText = load.map { String(format: "load %.2f %.2f %.2f", $0.0, $0.1, $0.2) } ?? ""
        return "\(shown.count) shown · \(threads) threads · \(loadText)"
    }

    // MARK: Table

    private var table: some View {
        Table(of: ProcessEntry.self, selection: $state.selection, sortOrder: $state.sortOrder,
              columnCustomization: $state.columns) {
            TableColumn("Process Name", value: \.name) { entry in
                HStack(spacing: 6) {
                    icon(for: entry)
                    Text(entry.name).lineLimit(1).truncationMode(.middle)
                }
                .font(rowFont)
            }
            .width(min: 180, ideal: 260)
            .customizationID("name")

            TableColumn("% CPU", value: \.cpuPercent) { entry in
                Text(String(format: "%.1f", entry.cpuPercent))
                    .font(rowFont)
                    .monospacedDigit()
                    .foregroundStyle(entry.cpuPercent >= 50 ? Color.orange : .primary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 56, ideal: 64)
            .customizationID("cpu")

            TableColumn("Memory", value: \.memoryBytes) { entry in
                Text(StatFormatting.bytes(entry.memoryBytes))
                    .font(rowFont)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 72, ideal: 84)
            .customizationID("memory")

            TableColumn("Threads", value: \.threads) { entry in
                Text(String(entry.threads))
                    .font(rowFont)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 56, ideal: 64)
            .customizationID("threads")

            TableColumn("PID", value: \.pid) { entry in
                Text(String(entry.pid))
                    .font(rowFont)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 56, ideal: 64)
            .customizationID("pid")

            TableColumn("User", value: \.ownerLabel) { entry in
                Text(entry.ownerLabel)
                    .font(rowFont)
                    .foregroundStyle(.secondary)
            }
            .width(min: 60, ideal: 70)
            .customizationID("user")

            // Off by default: with "All" selected the rows are already under their own headings.
            TableColumn("Kind", value: \.origin.rawValue) { entry in
                Label(entry.origin.title, systemImage: entry.origin.symbol)
                    .font(rowFont)
                    .foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 100)
            .customizationID("kind")
            .defaultVisibility(.hidden)
        } rows: {
            if state.scope == .all {
                ForEach(groups) { group in
                    Section {
                        ForEach(group.entries) { TableRow($0) }
                    } header: {
                        groupHeader(group)
                    }
                }
            } else {
                ForEach(entries) { TableRow($0) }
            }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .contextMenu(forSelectionType: ProcessEntry.ID.self) { ids in
            let chosen = entries.filter { ids.contains($0.id) }
            if chosen.count == 1, let entry = chosen.first {
                menu(for: entry)
            } else if chosen.count > 1 {
                // Quitting one of several selected rows without saying which is worse than not
                // offering it at all.
                Button("Copy \(chosen.count) PIDs") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(chosen.map { String($0.pid) }.joined(separator: " "), forType: .string)
                }
                Text("Select one process to quit it or keep the Mac awake until it exits.")
            }
        }
    }

    private func groupHeader(_ group: ProcessGroup) -> some View {
        HStack(spacing: 6) {
            Image(systemName: group.origin.symbol)
            Text(group.origin.title)
            Text("\(group.entries.count)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .font(.system(size: 11, weight: .semibold))
        .help(group.origin == .macOS
              ? "Shipped with macOS, from the protected system volume"
              : group.origin == .installed ? "Installed on this Mac" : "The path isn't readable — another user's process, or the kernel")
    }

    @ViewBuilder
    private func icon(for entry: ProcessEntry) -> some View {
        if let image = ProcessIcons.icon(forExecutable: entry.executablePath) {
            Image(nsImage: image).resizable().frame(width: 16, height: 16)
        } else {
            Image(systemName: entry.origin.symbol)
                .frame(width: 16, height: 16)
                .foregroundStyle(.secondary)
        }
    }

    private func notice(_ message: String) -> some View {
        HStack {
            Label(message, systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Dismiss") { state.message = nil }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: Actions

    @ViewBuilder
    private func menu(for entry: ProcessEntry) -> some View {
        Button("Keep Awake Until This Exits") { watch(entry) }
        Button("Copy PID") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(String(entry.pid), forType: .string)
        }
        Button("Reveal in Finder") { reveal(entry) }
        if entry.isOwn {
            Divider()
            Button("Quit…") {
                state.forceQuit = false
                state.confirmingQuit = entry
            }
            Button("Force Quit…", role: .destructive) {
                state.forceQuit = true
                state.confirmingQuit = entry
            }
        }
    }

    private func watch(_ entry: ProcessEntry) {
        do {
            let hold = try environment.controller.watchProcess(pid: entry.pid, policy: environment.controller.currentPolicy)
            state.message = "Keeping your Mac awake until \(hold.label) ends."
        } catch let error as AwakeError {
            state.message = error.message
        } catch {
            state.message = error.localizedDescription
        }
    }

    private func reveal(_ entry: ProcessEntry) {
        // The path sampled with the row, so this reveals the process the user right-clicked even if
        // that PID has been recycled since.
        guard let path = entry.executablePath else {
            state.message = "That process's location isn't readable."
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) // security-allow: reveal in Finder, user-initiated, shows a file and launches nothing else
    }

    private func confirmQuit() {
        guard let entry = state.confirmingQuit else { return }
        state.confirmingQuit = nil
        do {
            // The identity captured when the row was sampled: if this PID has been recycled since,
            // ProcessControl refuses rather than signalling whatever holds the number now.
            try ProcessControl().quit(entry.identity, force: state.forceQuit)
            state.message = "\(state.forceQuit ? "Force quit" : "Asked to quit"): \(entry.name)."
        } catch let error as ProcessControlError {
            state.message = error.message
        } catch {
            state.message = error.localizedDescription
        }
    }
}
