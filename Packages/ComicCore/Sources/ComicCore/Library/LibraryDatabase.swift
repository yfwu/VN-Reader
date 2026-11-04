import Foundation

/// JSON persistence of book records with atomic writes and a backup copy.
public final class LibraryDatabase: @unchecked Sendable {
    public struct Snapshot: Codable, Equatable {
        public var version: Int
        public var books: [BookRecord]
    }

    public static let currentVersion = 1
    private let paths: LibraryPaths
    private let queue = DispatchQueue(label: "vnreader.library.db")

    public init(paths: LibraryPaths) {
        self.paths = paths
    }

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

    public enum LoadResult: Equatable {
        case loaded([BookRecord])
        case empty
        /// Main file was unreadable; records came from the backup.
        case recoveredFromBackup([BookRecord])
    }

    /// Loads the library. A corrupt main file is preserved for diagnosis and the
    /// backup is used instead; the app never silently drops the library.
    public func load() -> LoadResult {
        queue.sync {
            let fm = FileManager.default
            if let books = try? readSnapshot(paths.libraryFile) {
                try? fm.removeItem(at: paths.libraryBackupFile)
                try? fm.copyItem(at: paths.libraryFile, to: paths.libraryBackupFile)
                return .loaded(books)
            }
            let mainExists = fm.fileExists(atPath: paths.libraryFile.path)
            if mainExists {
                let stamp = Int(Date().timeIntervalSince1970)
                try? fm.moveItem(at: paths.libraryFile, to: paths.root.appendingPathComponent("library.corrupt-\(stamp).json"))
            }
            if let books = try? readSnapshot(paths.libraryBackupFile) {
                try? writeSnapshot(books)
                return .recoveredFromBackup(books)
            }
            return .empty
        }
    }

    private func readSnapshot(_ url: URL) throws -> [BookRecord] {
        let data = try Data(contentsOf: url)
        return try LibraryDatabase.decoder().decode(Snapshot.self, from: data).books
    }

    private func writeSnapshot(_ books: [BookRecord]) throws {
        try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        let data = try LibraryDatabase.encoder().encode(Snapshot(version: LibraryDatabase.currentVersion, books: books))
        try data.write(to: paths.libraryFile, options: [.atomic])
    }

    /// Synchronous, atomic save. Safe to call from any thread.
    public func save(_ books: [BookRecord]) throws {
        try queue.sync { try writeSnapshot(books) }
    }
}
