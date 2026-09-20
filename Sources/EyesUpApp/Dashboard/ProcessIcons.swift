import AppKit
import SwiftUI

/// The real icon for each row, looked up once per executable and kept.
///
/// `NSWorkspace.icon(forFile:)` is a disk touch, and the table redraws every two seconds, so the
/// answers are cached. The cache is capped: a Mac can run a few hundred distinct binaries, and an
/// icon is small, but nothing here should grow without a limit.
@MainActor
enum ProcessIcons {
    private static var cache: [String: NSImage] = [:]
    private static var order: [String] = []
    private static let limit = 400

    /// The app's own icon when the binary lives inside a bundle, otherwise the executable's icon.
    static func icon(forExecutable path: String?) -> NSImage? {
        guard let path, !path.isEmpty else { return nil }
        let target = bundlePath(for: path) ?? path
        if let known = cache[target] { return known }
        guard FileManager.default.fileExists(atPath: target) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: target)
        image.size = NSSize(width: 16, height: 16)
        cache[target] = image
        order.append(target)
        if order.count > limit, let oldest = order.first {
            order.removeFirst()
            cache.removeValue(forKey: oldest)
        }
        return image
    }

    /// "/Applications/Claude.app/Contents/MacOS/Claude" → "/Applications/Claude.app".
    private static func bundlePath(for path: String) -> String? {
        guard let range = path.range(of: ".app/Contents/MacOS/") else { return nil }
        return String(path[path.startIndex..<range.lowerBound]) + ".app"
    }
}
