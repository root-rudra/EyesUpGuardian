import Foundation

/// The busiest processes, by CPU used between samples. Processes this user can't inspect are skipped.
public final class ProcessProbe {
    /// Enough for any table; a full sweep of ~340 processes costs about 2 ms.
    public static let limit = 100
    /// Names come from other processes, so they are trimmed of anything that could misrepresent a row.
    public static let maxNameLength = 40

    private let inspector: any ProcessInspecting
    private let clock: any WallClock
    private let ownUID: uid_t
    private var previous: [Int32: (cpuSeconds: Double, startTime: UInt64)] = [:]
    private var previousTime: Date?

    public init(inspector: any ProcessInspecting = LibprocInspector(), clock: any WallClock = SystemClock(), ownUID: uid_t = getuid()) {
        self.inspector = inspector
        self.clock = clock
        self.ownUID = ownUID
    }

    /// Strips control and formatting characters (a name can contain a right-to-left override) and caps length.
    static func displayName(_ raw: String) -> String {
        let cleaned = String(raw.unicodeScalars.filter { scalar in
            let category = scalar.properties.generalCategory
            return category != .control && category != .format && category != .lineSeparator
                && category != .paragraphSeparator
        })
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(maxNameLength))
    }

    public func sample() -> [ProcessEntry]? {
        let now = clock.now
        let elapsed = previousTime.map { now.timeIntervalSince($0) } ?? 0
        defer { previousTime = now }

        var entries: [ProcessEntry] = []
        var current: [Int32: (cpuSeconds: Double, startTime: UInt64)] = [:]
        for pid in inspector.allProcessIDs() {
            guard let detail = inspector.details(of: pid) else { continue }
            current[pid] = (detail.cpuSeconds, detail.identity.startTime)

            var percent = 0.0
            if elapsed > 0, let last = previous[pid], last.startTime == detail.identity.startTime,
               detail.cpuSeconds >= last.cpuSeconds {
                percent = (detail.cpuSeconds - last.cpuSeconds) / elapsed * 100
            }
            entries.append(ProcessEntry(
                pid: pid,
                identity: detail.identity,
                name: Self.displayName(detail.name),
                cpuPercent: percent,
                memoryBytes: detail.memoryBytes,
                threads: detail.threads,
                isOwn: detail.uid == ownUID
            ))
        }
        previous = current
        guard elapsed > 0 else { return [] } // first pass only sets the baseline
        return Array(entries.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(Self.limit))
    }
}
