import Foundation

/// On-disk layout. Permanent data lives under `root` (Application Support);
/// everything under `cachesRoot` can be deleted at any time and rebuilt.
///
///     <root>/library.json              book records (atomic writes)
///     <root>/library.backup.json       last known-good copy
///     <root>/Books/<id>/book.cbz|cbr   app-managed copy of the archive
///     <root>/Books/<id>/manifest.json  frozen page list
///     <root>/Books/<id>/cover.jpg      cover thumbnail
///     <cachesRoot>/Extracted/<id>/     solid-RAR page cache
///     <cachesRoot>/Thumbnails/<id>/    page thumbnails
///     <tempRoot>/Import/<job>/         staging area for in-flight imports
public struct LibraryPaths: Sendable {
    public let root: URL
    public let cachesRoot: URL
    public let tempRoot: URL

    public init(root: URL, cachesRoot: URL, tempRoot: URL) {
        self.root = root
        self.cachesRoot = cachesRoot
        self.tempRoot = tempRoot
    }

    /// Standard locations inside the app sandbox.
    public static func standard(fileManager: FileManager = .default) throws -> LibraryPaths {
        let support = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let caches = try fileManager.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return LibraryPaths(root: support.appendingPathComponent("VNReader", isDirectory: true),
                            cachesRoot: caches.appendingPathComponent("VNReader", isDirectory: true),
                            tempRoot: fileManager.temporaryDirectory.appendingPathComponent("VNReader", isDirectory: true))
    }

    public var libraryFile: URL { root.appendingPathComponent("library.json") }
    public var libraryBackupFile: URL { root.appendingPathComponent("library.backup.json") }
    public var booksDir: URL { root.appendingPathComponent("Books", isDirectory: true) }
    public var importStagingDir: URL { tempRoot.appendingPathComponent("Import", isDirectory: true) }
    public var extractedCacheDir: URL { cachesRoot.appendingPathComponent("Extracted", isDirectory: true) }
    public var thumbnailCacheDir: URL { cachesRoot.appendingPathComponent("Thumbnails", isDirectory: true) }

    public func bookDir(_ id: UUID) -> URL { booksDir.appendingPathComponent(id.uuidString, isDirectory: true) }
    public func archiveFile(_ id: UUID, format: ArchiveFormat) -> URL {
        bookDir(id).appendingPathComponent("book.\(format.managedExtension)")
    }
    public func manifestFile(_ id: UUID) -> URL { bookDir(id).appendingPathComponent("manifest.json") }
    public func coverFile(_ id: UUID) -> URL { bookDir(id).appendingPathComponent("cover.jpg") }
    public func extractedDir(_ id: UUID) -> URL { extractedCacheDir.appendingPathComponent(id.uuidString, isDirectory: true) }
    public func thumbnailDir(_ id: UUID) -> URL { thumbnailCacheDir.appendingPathComponent(id.uuidString, isDirectory: true) }

    public func createDirectories(fileManager: FileManager = .default) throws {
        for d in [root, booksDir, cachesRoot, extractedCacheDir, thumbnailCacheDir, importStagingDir] {
            try fileManager.createDirectory(at: d, withIntermediateDirectories: true)
        }
    }
}
