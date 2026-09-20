import EyesUpCore
import Foundation

/// Turns a sample into the rows the table shows: scope, search, sort, and the groups.
///
/// It lives apart from the view so the rules can be tested — a table that quietly drops rows or
/// files them under the wrong heading is hard to notice by looking.
enum ProcessTableModel {
    static func rows(
        from all: [ProcessEntry],
        scope: ProcessScope,
        filter: String,
        sortOrder: [KeyPathComparator<ProcessEntry>]
    ) -> [ProcessEntry] {
        let scoped = scope.origin.map { origin in all.filter { $0.origin == origin } } ?? all
        let text = filter.trimmingCharacters(in: .whitespaces)
        let filtered = text.isEmpty
            ? scoped
            : scoped.filter { $0.name.localizedCaseInsensitiveContains(text) || String($0.pid).contains(text) }
        return filtered.sorted(using: sortOrder)
    }

    /// Groups in a fixed order — macOS, Installed, Other — leaving out any group with no rows.
    static func groups(of rows: [ProcessEntry]) -> [ProcessGroup] {
        ProcessOrigin.allCases.compactMap { origin in
            let group = rows.filter { $0.origin == origin }
            return group.isEmpty ? nil : ProcessGroup(origin: origin, entries: group)
        }
    }
}
