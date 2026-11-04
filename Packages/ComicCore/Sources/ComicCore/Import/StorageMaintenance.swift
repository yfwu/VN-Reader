import Foundation

/// Housekeeping for app storage. Run at launch (before imports start) and after deletions.
public enum StorageMaintenance {
    public struct Report: Equatable {
        public var removedStagingJobs = 0
        public var removedOrphanBooks = 0
        public var removedOrphanCaches = 0
    }

    /// Removes interrupted imports, book folders without a library record, and
    /// caches of books that no longer exist.
    @discardableResult
    public static func cleanUp(paths: LibraryPaths, knownBooks: Set<UUID>) -> Report {
        let fm = FileManager.default
        var report = Report()
        if let jobs = try? fm.contentsOfDirectory(at: paths.importStagingDir, includingPropertiesForKeys: nil) {
            for j in jobs where (try? fm.removeItem(at: j)) != nil { report.removedStagingJobs += 1 }
        }
        func sweep(_ dir: URL, counter: inout Int) {
            guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
            for item in items {
                guard let id = UUID(uuidString: item.lastPathComponent), knownBooks.contains(id) else {
                    if (try? fm.removeItem(at: item)) != nil { counter += 1 }
                    continue
                }
            }
        }
        sweep(paths.booksDir, counter: &report.removedOrphanBooks)
        sweep(paths.extractedCacheDir, counter: &report.removedOrphanCaches)
        sweep(paths.thumbnailCacheDir, counter: &report.removedOrphanCaches)
        return report
    }

    /// Deletes the app-managed copy and all caches of a book. Never touches the user's original file.
    public static func deleteBook(_ id: UUID, paths: LibraryPaths) {
        let fm = FileManager.default
        BookPageSource.stopBackgroundWork(bookID: id, paths: paths)
        try? fm.removeItem(at: paths.bookDir(id))
        try? fm.removeItem(at: paths.extractedDir(id))
        try? fm.removeItem(at: paths.thumbnailDir(id))
    }

    public static func clearCaches(paths: LibraryPaths, except keep: Set<UUID> = []) {
        let fm = FileManager.default
        for dir in [paths.extractedCacheDir, paths.thumbnailCacheDir] {
            for item in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] {
                if let id = UUID(uuidString: item.lastPathComponent), keep.contains(id) { continue }
                try? fm.removeItem(at: item)
            }
        }
    }

    public static func directorySize(_ url: URL) -> Int64 {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in e {
            if let v = try? f.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]), v.isRegularFile == true {
                total += Int64(v.fileSize ?? 0)
            }
        }
        return total
    }

    /// Keeps the solid-RAR extraction cache under `limit` bytes by removing the
    /// least recently used books (directory modification date), except `keep`.
    public static func trimExtractedCache(paths: LibraryPaths, limit: Int64, keep: Set<UUID>) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: paths.extractedCacheDir,
                                                      includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        var entries = items.map { url -> (URL, Date, Int64) in
            let d = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return (url, d ?? .distantPast, directorySize(url))
        }
        var total = entries.reduce(0) { $0 + $1.2 }
        entries.sort { $0.1 < $1.1 }
        for (url, _, size) in entries where total > limit {
            if let id = UUID(uuidString: url.lastPathComponent), keep.contains(id) { continue }
            try? fm.removeItem(at: url)
            total -= size
        }
    }
}
