/// Turns the current set of holds into the minimum set of power assertions (at most one per kind).
@MainActor
public final class AwakeEngine {
    public static let maxNameLength = 128

    public private(set) var active: [AssertionKind: UInt32] = [:]
    public private(set) var lastError: PowerAssertionError?
    private var currentName = ""
    private let provider: any PowerAssertionProviding

    public init(provider: any PowerAssertionProviding) {
        self.provider = provider
    }

    public func reconcile(holds: [Hold]) {
        let desired = holds.reduce(into: Set<AssertionKind>()) { $0.formUnion(AssertionKind.kinds(for: $1.policy)) }
        let name = Self.assertionName(for: holds)
        lastError = nil

        for (kind, id) in active where !desired.contains(kind) {
            provider.release(id)
            active[kind] = nil
        }
        if name != currentName {
            for id in active.values { provider.rename(id, to: name) }
        }
        for kind in AssertionKind.allCases where desired.contains(kind) && active[kind] == nil {
            do {
                active[kind] = try provider.create(kind, name: name)
            } catch let error as PowerAssertionError {
                lastError = error
            } catch {
                lastError = PowerAssertionError(kind: kind, code: -1)
            }
        }
        currentName = active.isEmpty ? "" : name
    }

    public func releaseAll() {
        reconcile(holds: [])
    }

    /// "EyesUpGuardian: Timer 2h · Claude running", visible in `pmset -g assertions`.
    public static func assertionName(for holds: [Hold]) -> String {
        let prefix = "EyesUpGuardian"
        guard !holds.isEmpty else { return prefix }
        let full = printable(prefix + ": " + holds.map(\.label).joined(separator: " · "))
        guard full.count > maxNameLength else { return full }
        return String(full.prefix(maxNameLength - 1)) + "…"
    }

    /// macOS formats times with a narrow no-break space (U+202F), and `pmset -g assertions` prints
    /// an empty name when one is present. Exotic whitespace becomes a plain space so the audit trail stays readable.
    static func printable(_ name: String) -> String {
        String(name.map { character in
            character.unicodeScalars.allSatisfy { $0.properties.isWhitespace && !$0.isASCII } ? " " : character
        })
    }
}
