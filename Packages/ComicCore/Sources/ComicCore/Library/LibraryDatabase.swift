import Foundation

/// Atomic JSON persistence. Failed recovery never becomes an empty, writable library.
public final class LibraryDatabase: @unchecked Sendable {
    public struct Snapshot: Codable, Equatable {
        public var version: Int
        public var books: [BookRecord]
    }

    public static let currentVersion = 2
    private let paths: LibraryPaths
    private let queue = DispatchQueue(label: "vnreader.library.db")
    private var writeProtection: PersistenceError?

    public init(paths: LibraryPaths) { self.paths = paths }

    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }

    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    public enum PersistenceError: Error, Equatable {
        case unavailable
        case unsupportedVersion(Int)
    }

    public enum LoadResult: Equatable {
        case loaded([BookRecord])
        /// No saved library, backup or managed books exist yet.
        case empty
        case recoveredFromBackup([BookRecord])
        /// Saved data exists but cannot be recovered. Files and writes are protected.
        case unavailable
        /// Do not fall back to an older backup or overwrite a newer schema.
        case unsupportedVersion(Int)
    }

    private enum ReadResult {
        case valid([BookRecord], Data)
        case missing
        case unreadable
        case unsupported(Int)
    }

    /// Preserves unreadable files and only restores a validated, supported backup.
    /// Orphaned book folders are deliberately left in place by storage maintenance.
    public func load() -> LoadResult {
        queue.sync {
            let main = readSnapshot(paths.libraryFile)
            switch main {
            case .valid(let books, _):
                writeProtection = nil
                return .loaded(books)
            case .unsupported(let version):
                writeProtection = .unsupportedVersion(version)
                return .unsupportedVersion(version)
            case .missing, .unreadable:
                break
            }

            switch readSnapshot(paths.libraryBackupFile) {
            case .valid(let books, let data):
                do {
                    // Copy, rather than move, so a failed repair leaves the original
                    // main file present and the next launch cannot mistake it for new.
                    if case .unreadable = main {
                        let preserved = paths.root.appendingPathComponent("library.corrupt-\(UUID().uuidString).json")
                        try FileManager.default.copyItem(at: paths.libraryFile, to: preserved)
                    }
                    try data.write(to: paths.libraryFile, options: .atomic)
                    writeProtection = nil
                    return .recoveredFromBackup(books)
                } catch {
                    writeProtection = .unavailable
                    return .unavailable
                }
            case .unsupported(let version):
                writeProtection = .unsupportedVersion(version)
                return .unsupportedVersion(version)
            case .missing:
                if case .missing = main, isNewLibrary {
                    writeProtection = nil
                    return .empty
                }
            case .unreadable:
                break
            }
            writeProtection = .unavailable
            return .unavailable
        }
    }

    private var isNewLibrary: Bool {
        // Failure to inspect storage is not evidence of an empty library.
        let fm = FileManager.default
        if !fm.fileExists(atPath: paths.booksDir.path) { return true }
        guard let books = try? fm.contentsOfDirectory(at: paths.booksDir, includingPropertiesForKeys: nil) else { return false }
        return books.isEmpty
    }

    private func readSnapshot(_ url: URL) -> ReadResult {
        let data: Data
        do { data = try Data(contentsOf: url) }
        catch {
            let e = error as NSError
            return e.domain == NSCocoaErrorDomain && e.code == NSFileReadNoSuchFileError ? .missing : .unreadable
        }
        do {
            // Inspect the version before decoding records: future records may use
            // types this build cannot decode and must not trigger backup recovery.
            struct Header: Decodable { var version: Int }
            let version = try Self.decoder().decode(Header.self, from: data).version
            guard (1...Self.currentVersion).contains(version) else { return .unsupported(version) }
            return .valid(try Self.decoder().decode(Snapshot.self, from: data).books, data)
        } catch { return .unreadable }
    }

    /// A successful return means the main snapshot is durable. Refreshing its backup
    /// is best effort; a backup error must not make an already committed import fail.
    public func save(_ books: [BookRecord]) throws {
        try queue.sync {
            if let writeProtection { throw writeProtection }
            // Also guard callers that save without first calling load().
            switch readSnapshot(paths.libraryFile) {
            case .unsupported(let version): throw PersistenceError.unsupportedVersion(version)
            case .unreadable: throw PersistenceError.unavailable
            case .valid, .missing: break
            }
            try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
            // Preserve the complete v1 snapshot before the first v2 write. A failed
            // backup prevents migration, and a later downgrade refuses schema 2.
            if let original = try? Data(contentsOf: paths.libraryFile),
               let header = try? JSONSerialization.jsonObject(with: original) as? [String: Any],
               (header["version"] as? Int) == 1 {
                let migrationBackup = paths.root.appendingPathComponent("library.before-v2.json")
                if !FileManager.default.fileExists(atPath: migrationBackup.path) {
                    try original.write(to: migrationBackup, options: [.atomic])
                }
            }
            let data = try Self.encoder().encode(Snapshot(version: Self.currentVersion, books: books))
            try data.write(to: paths.libraryFile, options: .atomic)
            // Atomic replacement keeps the previous backup if the new copy fails.
            try? data.write(to: paths.libraryBackupFile, options: .atomic)
        }
    }
}
