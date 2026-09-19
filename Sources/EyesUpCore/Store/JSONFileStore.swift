import Foundation

public enum StoreLoadResult<Value> {
    case missing
    case loaded(Value)
    /// The file was unreadable. It was moved to `movedTo` (nil if moving failed and it was deleted).
    case corrupt(movedTo: URL?)
}

extension StoreLoadResult: Sendable where Value: Sendable {}

/// A versioned JSON file, written atomically. Bad files are moved aside, never crashed on.
public struct JSONFileStore<Value: Codable & Sendable>: Sendable {
    public static var maxFileSize: Int { 5 * 1024 * 1024 }

    public let url: URL
    public let schemaVersion: Int

    private struct Envelope: Codable {
        var schemaVersion: Int
        var value: Value
    }

    public init(url: URL, schemaVersion: Int) {
        self.url = url
        self.schemaVersion = schemaVersion
    }

    public func load(now: Date = Date()) -> StoreLoadResult<Value> {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return .missing }

        if let size = (try? fileManager.attributesOfItem(atPath: url.path))?[.size] as? Int, size > Self.maxFileSize {
            return .corrupt(movedTo: moveAside(now: now))
        }
        guard let data = try? Data(contentsOf: url),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.schemaVersion == schemaVersion else {
            return .corrupt(movedTo: moveAside(now: now))
        }
        return .loaded(envelope.value)
    }

    public func save(_ value: Value) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Envelope(schemaVersion: schemaVersion, value: value)).write(to: url, options: .atomic)
    }

    private func moveAside(now: Date) -> URL? {
        let stem = url.deletingPathExtension().lastPathComponent
        let target = url.deletingLastPathComponent()
            .appendingPathComponent("\(stem).corrupt-\(Int(now.timeIntervalSince1970)).json")
        do {
            try FileManager.default.moveItem(at: url, to: target)
            return target
        } catch {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }
}

public enum StorageLocation {
    /// ~/Library/Application Support/EyesUpGuardian
    public static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EyesUpGuardian", isDirectory: true)
    }
}
