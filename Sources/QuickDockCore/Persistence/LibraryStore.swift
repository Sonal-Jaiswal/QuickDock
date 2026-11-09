import Foundation

/// Reads and writes `library.json`, QuickDock's single source of truth for items.
///
/// Data-loss protections:
///  • Writes are atomic (written to a temporary file, then renamed into place).
///  • Before each write the previous good file is copied to `library.backup.json`.
///  • A file that cannot be decoded is never overwritten: it is moved aside as
///    `library.unreadable-<timestamp>.json` and the backup is used instead.
///  • A file written by a newer QuickDock (higher schema version) is preserved the same way.
public final class LibraryStore {
    public enum LoadResult: Equatable {
        /// No library exists yet (first launch).
        case empty
        case loaded(LibrarySnapshot)
        /// The main file was unreadable; data came from the backup (or is empty if
        /// the backup was unusable too). The unreadable file was preserved at `preservedFile`.
        case recovered(LibrarySnapshot, preservedFile: URL, fromBackup: Bool)
    }

    public enum StoreError: Error, LocalizedError {
        case writeFailed(underlying: Error)

        public var errorDescription: String? {
            switch self {
            case .writeFailed(let error): return "QuickDock couldn’t save your items. \(error.localizedDescription)"
            }
        }
    }

    public let directory: URL
    public var fileURL: URL { directory.appendingPathComponent("library.json") }
    public var backupURL: URL { directory.appendingPathComponent("library.backup.json") }

    private let fileManager: FileManager

    public init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    /// `~/Library/Application Support/QuickDock` (inside the sandbox container when sandboxed).
    public static func defaultDirectory(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("QuickDock", isDirectory: true)
    }

    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public func load() -> LoadResult {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            // Main file missing but a backup exists (e.g. interrupted first write): use it.
            if let backup = try? decode(at: backupURL) {
                return .loaded(backup)
            }
            return .empty
        }
        do {
            return .loaded(try decode(at: fileURL))
        } catch {
            let preserved = preserveUnreadableFile()
            if let backup = try? decode(at: backupURL) {
                return .recovered(backup, preservedFile: preserved, fromBackup: true)
            }
            return .recovered(.empty, preservedFile: preserved, fromBackup: false)
        }
    }

    public func save(_ snapshot: LibrarySnapshot) throws {
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try Self.makeEncoder().encode(snapshot)
            // Keep the last good version as a backup before replacing it.
            if fileManager.fileExists(atPath: fileURL.path), (try? decode(at: fileURL)) != nil {
                try? fileManager.removeItem(at: backupURL)
                try? fileManager.copyItem(at: fileURL, to: backupURL)
            }
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            throw StoreError.writeFailed(underlying: error)
        }
    }

    /// Deletes the library and its backup (used by "Reset QuickDock").
    public func deleteAll() throws {
        for url in [fileURL, backupURL] where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private enum DecodeError: Error { case unsupportedSchema(Int) }

    private func decode(at url: URL) throws -> LibrarySnapshot {
        let data = try Data(contentsOf: url)
        let snapshot = try Self.makeDecoder().decode(LibrarySnapshot.self, from: data)
        guard snapshot.schemaVersion <= LibrarySnapshot.currentSchemaVersion else {
            throw DecodeError.unsupportedSchema(snapshot.schemaVersion)
        }
        return snapshot
    }

    private func preserveUnreadableFile() -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        var destination = directory.appendingPathComponent("library.unreadable-\(formatter.string(from: Date())).json")
        var counter = 1
        while fileManager.fileExists(atPath: destination.path) {
            destination = directory.appendingPathComponent("library.unreadable-\(formatter.string(from: Date()))-\(counter).json")
            counter += 1
        }
        do {
            try fileManager.moveItem(at: fileURL, to: destination)
            return destination
        } catch {
            return fileURL
        }
    }
}
