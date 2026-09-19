import AppKit
import EyesUpCore
import SwiftUI

enum ProcessSort: String, CaseIterable, Identifiable {
    case cpu, memory, name

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memory"
        case .name: "Name"
        }
    }
}

@MainActor
@Observable
final class ProcessesState {
    var filter = ""
    var sort: ProcessSort = .cpu
    var confirmingQuit: ProcessEntry?
    var forceQuit = false
    var message: String?
}

/// The dense "Mission Control" table (spec §7.3).
struct ProcessesTab: View {
    let environment: AppEnvironment
    @Bindable var stats: StatsViewModel
    @Bindable var state: ProcessesState

    private var entries: [ProcessEntry] {
        let all = stats.snapshot.processes ?? []
        let filtered = state.filter.isEmpty
            ? all
            : all.filter { $0.name.localizedCaseInsensitiveContains(state.filter) || String($0.pid).contains(state.filter) }
        return switch state.sort {
        case .cpu: filtered.sorted { $0.cpuPercent > $1.cpuPercent }
        case .memory: filtered.sorted { $0.memoryBytes > $1.memoryBytes }
        case .name: filtered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            table
            if let message = state.message {
                Label(message, systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary).padding(8)
            }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.7))
        .font(.system(size: 11, design: .monospaced))
        .onAppear { stats.start() }
        .onDisappear { stats.stop() }
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

    private var header: some View {
        HStack(spacing: 12) {
            Text("Processes").font(.system(size: 13, weight: .semibold))
            Text(summary).foregroundStyle(.secondary)
            Spacer()
            Picker("Sort", selection: $state.sort) {
                ForEach(ProcessSort.allCases) { sort in Text(sort.title).tag(sort) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            TextField("Filter", text: $state.filter)
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)
        }
        .padding(10)
    }

    private var summary: String {
        let all = stats.snapshot.processes ?? []
        let threads = all.reduce(0) { $0 + $1.threads }
        let load = stats.snapshot.system?.loadAverage
        let loadText = load.map { String(format: "load %.2f %.2f %.2f", $0.0, $0.1, $0.2) } ?? ""
        return "\(all.count) shown · \(threads) threads · \(loadText)"
    }

    private var table: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                row(name: "NAME", pid: "PID", cpu: "CPU%", memory: "MEM", threads: "THR", user: "USER")
                    .foregroundStyle(.secondary)
                ForEach(entries) { entry in
                    row(name: entry.name, pid: String(entry.pid),
                        cpu: String(format: "%.1f", entry.cpuPercent),
                        memory: StatFormatting.bytes(entry.memoryBytes),
                        threads: String(entry.threads),
                        user: entry.isOwn ? "you" : "sys")
                    .contentShape(Rectangle())
                    .contextMenu { menu(for: entry) }
                }
            }
        }
    }

    private func row(name: String, pid: String, cpu: String, memory: String, threads: String, user: String) -> some View {
        HStack(spacing: 8) {
            Text(name).frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
            Text(pid).frame(width: 60, alignment: .trailing)
            Text(cpu).frame(width: 60, alignment: .trailing)
            Text(memory).frame(width: 80, alignment: .trailing)
            Text(threads).frame(width: 45, alignment: .trailing)
            Text(user).frame(width: 40, alignment: .trailing).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func menu(for entry: ProcessEntry) -> some View {
        Button("Keep awake until this exits") { watch(entry) }
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
        guard let path = LibprocInspector().executablePath(of: entry.pid) else {
            state.message = "That process's location isn't readable."
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private func confirmQuit() {
        guard let entry = state.confirmingQuit else { return }
        state.confirmingQuit = nil
        let inspector = LibprocInspector()
        guard let identity = inspector.identity(of: entry.pid) else {
            state.message = ProcessControlError.gone.message
            return
        }
        do {
            try ProcessControl().quit(identity, force: state.forceQuit)
            state.message = "\(state.forceQuit ? "Force quit" : "Asked to quit"): \(entry.name)."
        } catch let error as ProcessControlError {
            state.message = error.message
        } catch {
            state.message = error.localizedDescription
        }
    }
}
