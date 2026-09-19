public struct PowerAssertionError: Error, Equatable, Sendable {
    public let kind: AssertionKind
    /// The IOReturn code macOS returned.
    public let code: Int32

    public init(kind: AssertionKind, code: Int32) {
        self.kind = kind
        self.code = code
    }
}

/// The only way the app touches macOS power management. Tests substitute a fake.
@MainActor
public protocol PowerAssertionProviding: AnyObject {
    func create(_ kind: AssertionKind, name: String) throws -> UInt32
    func rename(_ id: UInt32, to name: String)
    func release(_ id: UInt32)
    /// caffeinate -u: report user activity so the display wakes and idle timers reset.
    func declareUserActivity(name: String)
}
