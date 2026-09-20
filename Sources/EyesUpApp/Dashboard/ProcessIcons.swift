import AppKit
import SwiftUI

/// The real icon for each row, looked up once per executable and kept.
///
/// `NSWorkspace.icon(forFile:)` is a disk touch, and the table redraws every two seconds, so the
/// answers are cached. The cache is capped: a Mac can run a few hundred distinct binaries, and an
/// icon is small, but nothing here should grow without a limit.
@MainActor
enum ProcessIcons {
    /// A miss is cached as nil: without that, a deleted or unreadable binary costs a `stat` on
    /// every redraw of the table.
    private static var cache: [String: NSImage?] = [:]
    private static var order: [String] = []
    /// A table shows about a hundred rows; this is headroom, not a target.
    private static let limit = 200

    /// The app's own icon when the binary lives inside a bundle, otherwise the executable's icon.
    static func icon(forExecutable path: String?) -> NSImage? {
        guard let path, !path.isEmpty else { return nil }
        let target = bundlePath(for: path) ?? path
        if let known = cache[target] { return known }
        let image: NSImage? = FileManager.default.fileExists(atPath: target)
            ? NSWorkspace.shared.icon(forFile: target)
            : nil
        image?.size = NSSize(width: 16, height: 16)
        cache[target] = image
        order.append(target)
        if order.count > limit, let oldest = order.first {
            order.removeFirst()
            cache.removeValue(forKey: oldest)
        }
        return image
    }

    /// Called when the Processes tab goes away: the app's idle footprint is a claim in the README,
    /// and icons kept from a table nobody is looking at would quietly raise it.
    static func forget() {
        cache.removeAll()
        order.removeAll()
    }

    /// "/Applications/Claude.app/Contents/MacOS/Claude" → "/Applications/Claude.app".
    private static func bundlePath(for path: String) -> String? {
        guard let range = path.range(of: ".app/Contents/MacOS/") else { return nil }
        return String(path[path.startIndex..<range.lowerBound]) + ".app"
    }
}
