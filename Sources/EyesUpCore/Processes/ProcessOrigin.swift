import Foundation

/// Where a running process came from: macOS itself, or something installed on this Mac.
///
/// It is decided from the executable's path, which is what System Integrity Protection actually
/// guarantees: nothing but the OS installer can put a binary under `/System`, `/bin`, `/sbin`,
/// `/usr` (except `/usr/local`) or `/Library/Apple`. Checking code signatures would be stricter,
/// but it costs a signature validation per process on every sample, and this table refreshes while
/// you watch it.
public enum ProcessOrigin: String, Codable, CaseIterable, Sendable {
    /// Shipped with macOS and protected by the system volume.
    case macOS
    /// An app or tool installed on this Mac — including Apple apps installed separately, like Xcode.
    case installed
    /// The path isn't readable: another user's process, or the kernel itself.
    case unknown

    public var title: String {
        switch self {
        case .macOS: "macOS"
        case .installed: "Installed"
        case .unknown: "Other"
        }
    }

    public var symbol: String {
        switch self {
        case .macOS: "apple.logo"
        case .installed: "shippingbox"
        case .unknown: "questionmark.circle"
        }
    }

    /// Paths only the OS installer can write to. `/usr/local` is deliberately missing: it is the
    /// one part of `/usr` that isn't protected, and it is where Homebrew and hand-installed tools go.
    private static let systemPrefixes = [
        "/System/",
        "/bin/",
        "/sbin/",
        "/usr/bin/",
        "/usr/sbin/",
        "/usr/libexec/",
        "/usr/lib/",
        "/usr/share/",
        "/Library/Apple/",
    ]

    public static func of(executablePath path: String?) -> ProcessOrigin {
        guard let path, path.hasPrefix("/") else { return .unknown }
        // `/System/Volumes/Data/...` is the writable data volume seen through a firmlink, not the
        // sealed system volume. Calling anything under it "shipped with macOS" is the one mistake
        // this classification cannot afford.
        if path.hasPrefix("/System/Volumes/") { return .installed }
        if systemPrefixes.contains(where: { path.hasPrefix($0) }) { return .macOS }
        return .installed
    }
}
