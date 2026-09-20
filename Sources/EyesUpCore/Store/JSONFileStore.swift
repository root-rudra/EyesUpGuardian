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
    /// How many moved-aside copies to keep, so a repeatedly corrupted file can't fill the folder.
    public static var keptCorruptFiles: Int { 2 }

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
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        guard let data = readRegularFile(),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.schemaVersion == schemaVersion else {
            return .corrupt(movedTo: moveAside(now: now))
        }
        return .loaded(envelope.value)
    }

    /// Reads the file only if it is a regular file this process opened directly.
    ///
    /// A symlink reports its own size to `stat`, so checking the path's size and then reading the path
    /// lets someone point the store at any file the user can read — or at a FIFO, which would block the
    /// read forever. `O_NOFOLLOW` refuses the symlink, `O_NONBLOCK` stops a FIFO from hanging the open,
    /// and the type and size are checked on the descriptor actually being read.
    private func readRegularFile() -> Data? {
        let descriptor = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        }
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }

        var info = stat()
        guard fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_size > 0,
              info.st_size <= Self.maxFileSize else { return nil }

        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        return try? handle.read(upToCount: Self.maxFileSize)
    }

    public func save(_ value: Value) throws {
        let directory = url.deletingLastPathComponent()
        // Only this user needs to know which apps and processes are being watched.
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Envelope(schemaVersion: schemaVersion, value: value)).write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    /// Keeps only the newest few copies: a file that is corrupt at every launch would otherwise
    /// leave one behind each time.
    private func pruneCorruptFiles(keeping newest: URL) {
        let directory = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        let copies = names
            .filter { $0.hasPrefix("\(stem).corrupt-") }
            .sorted()
        guard copies.count > Self.keptCorruptFiles else { return }
        for name in copies.dropLast(Self.keptCorruptFiles) where name != newest.lastPathComponent {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    private func moveAside(now: Date) -> URL? {
        let stem = url.deletingPathExtension().lastPathComponent
        let target = url.deletingLastPathComponent()
            .appendingPathComponent("\(stem).corrupt-\(Int(now.timeIntervalSince1970)).json")
        do {
            try FileManager.default.moveItem(at: url, to: target)
            pruneCorruptFiles(keeping: target)
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
