import Foundation
import Testing
@testable import EyesUpApp
@testable import EyesUpCore

@Suite @MainActor struct ProcessTableModelTests {
    private func entry(_ pid: Int32, _ name: String, cpu: Double, origin: ProcessOrigin,
                       memory: UInt64 = 1000) -> ProcessEntry {
        ProcessEntry(pid: pid, identity: ProcessIdentity(pid: pid, startTime: UInt64(pid)), name: name,
                     cpuPercent: cpu, memoryBytes: memory, threads: 2, isOwn: true, origin: origin,
                     executablePath: origin == .macOS ? "/usr/bin/\(name)" : "/Applications/\(name).app/Contents/MacOS/\(name)")
    }

    private var sample: [ProcessEntry] {
        [entry(1, "WindowServer", cpu: 8, origin: .macOS),
         entry(2, "Claude", cpu: 22, origin: .installed),
         entry(3, "kernel_task", cpu: 3, origin: .unknown),
         entry(4, "Finder", cpu: 1, origin: .macOS)]
    }

    private let byCPU = [KeyPathComparator(\ProcessEntry.cpuPercent, order: .reverse)]

    @Test func scopeShowsOnlyThatKindOfProcess() {
        let macOS = ProcessTableModel.rows(from: sample, scope: .macOS, filter: "", sortOrder: byCPU)
        #expect(macOS.map(\.name) == ["WindowServer", "Finder"])

        let installed = ProcessTableModel.rows(from: sample, scope: .installed, filter: "", sortOrder: byCPU)
        #expect(installed.map(\.name) == ["Claude"])

        #expect(ProcessTableModel.rows(from: sample, scope: .all, filter: "", sortOrder: byCPU).count == 4)
    }

    @Test func searchMatchesNamesAndPIDsWithinTheScope() {
        #expect(ProcessTableModel.rows(from: sample, scope: .all, filter: "clau", sortOrder: byCPU).map(\.name) == ["Claude"])
        #expect(ProcessTableModel.rows(from: sample, scope: .all, filter: "4", sortOrder: byCPU).map(\.name) == ["Finder"])
        // A search that matches nothing in this scope shows nothing, rather than falling back to all.
        #expect(ProcessTableModel.rows(from: sample, scope: .macOS, filter: "claude", sortOrder: byCPU).isEmpty)
        #expect(ProcessTableModel.rows(from: sample, scope: .all, filter: "   ", sortOrder: byCPU).count == 4)
    }

    @Test func sortingFollowsTheColumnTheUserClicked() {
        let byName = [KeyPathComparator(\ProcessEntry.name, order: .forward)]
        #expect(ProcessTableModel.rows(from: sample, scope: .all, filter: "", sortOrder: byName).map(\.name)
                == ["Claude", "Finder", "kernel_task", "WindowServer"])
        #expect(ProcessTableModel.rows(from: sample, scope: .all, filter: "", sortOrder: byCPU).map(\.name)
                == ["Claude", "WindowServer", "kernel_task", "Finder"])
    }

    @Test func groupsKeepTheirOrderAndEveryRow() {
        let rows = ProcessTableModel.rows(from: sample, scope: .all, filter: "", sortOrder: byCPU)
        let groups = ProcessTableModel.groups(of: rows)
        #expect(groups.map(\.origin) == [.macOS, .installed, .unknown])
        #expect(groups.map { $0.entries.count } == [2, 1, 1])
        // Nothing is lost or duplicated by grouping.
        #expect(groups.flatMap { $0.entries }.count == rows.count)
        // Within a group, the table's sort still holds.
        #expect(groups[0].entries.map(\.name) == ["WindowServer", "Finder"])
    }

    @Test func anEmptyGroupIsLeftOutRatherThanShownEmpty() {
        let onlyApple = sample.filter { $0.origin == .macOS }
        #expect(ProcessTableModel.groups(of: onlyApple).map(\.origin) == [.macOS])
    }
}
