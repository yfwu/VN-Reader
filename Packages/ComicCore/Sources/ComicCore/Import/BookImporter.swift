import Foundation

public struct ImportLimits: Sendable {
    public var maxFileSize: UInt64 = 8 * 1024 * 1024 * 1024
    public var archive = ArchiveLimits.default
    public var maxPages = 10_000
    public init() {}
}

public struct ImportProgress: Sendable, Equatable {
    public enum Phase: String, Sendable { case copying, inspecting, generatingCover, finishing }
    public var phase: Phase
    /// 0...1 within the copying phase; nil when indeterminate.
    public var fraction: Double?
}

public enum ImportOutcome: Equatable, Sendable {
    case imported(BookRecord)
    /// Same content already in the library — nothing was added or replaced.
    case duplicate(existing: UUID)
}

/// Renders a JPEG cover thumbnail from page image data (ImageIO on Apple platforms).
public protocol CoverRendering: Sendable {
    func coverJPEG(from imageData: Data) -> Data?
}

/// Brings an archive into app storage, validates it and creates a book record.
///
/// Guarantees:
/// - Nothing appears in the library until every step succeeded.
/// - On error or cancellation all staged / partially moved files are removed.
/// - Existing books are never overwritten: managed files are keyed by UUID.
/// - Duplicate rule: identical content (size + CRC-32 of the whole file) is
///   reported as `.duplicate` and not imported again. Different content with the
///   same name is imported as a separate book, with " (2)", " (3)"… appended.
public final class BookImporter: @unchecked Sendable {
    public let paths: LibraryPaths
    public var limits = ImportLimits()
    public var diskSpace: DiskSpaceProviding = SystemDiskSpace()
    public var coverRenderer: CoverRendering?
    /// Off forces a real copy (tests of the copy path).
    var allowsCloning = true
    private let fm = FileManager.default

    public init(paths: LibraryPaths, coverRenderer: CoverRendering? = nil) {
        self.paths = paths
        self.coverRenderer = coverRenderer
    }

    /// - Parameters:
    ///   - source: a readable local URL (the caller handles security scope / coordination).
    ///   - existing: current library records (for duplicate and name checks).
    public func importBook(from source: URL, existing: [BookRecord],
                           progress: @escaping (ImportProgress) -> Void = { _ in },
                           isCancelled: @escaping () -> Bool = { false }) throws -> ImportOutcome {
        try paths.createDirectories()
        let job = paths.importStagingDir.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: job, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: job) }

        // 1. Clone or copy into the staging area (progress, cancellation, CRC on the fly).
        progress(ImportProgress(phase: .copying, fraction: 0))
        let staged = job.appendingPathComponent("archive.bin")
        let (size, crc) = try stageFile(from: source, to: staged, progress: progress, isCancelled: isCancelled)
        let fingerprint = String(format: "%08x-%llu", crc, size)
        if let dup = existing.first(where: { $0.fingerprint == fingerprint }) {
            return .duplicate(existing: dup.id)
        }

        // 2. Inspect by content.
        progress(ImportProgress(phase: .inspecting, fraction: nil))
        if isCancelled() { throw ComicError.cancelled }
        let archive = try ArchiveOpener.open(url: staged, limits: limits.archive)
        let manifest = try PageManifest.build(from: archive)
        guard manifest.pageCount <= limits.maxPages else {
            throw ComicError.tooManyEntries(count: manifest.pageCount, limit: limits.maxPages)
        }
        if isCancelled() { throw ComicError.cancelled }

        var metadata: ComicMetadata? = nil
        if let ci = manifest.comicInfoIndex, let xml = try? archive.readEntry(at: ci) {
            metadata = ComicInfoParser.parse(xml)
        }

        // 3. Cover: first decodable page among the first few.
        progress(ImportProgress(phase: .generatingCover, fraction: nil))
        var cover: Data? = nil
        if let renderer = coverRenderer {
            for page in manifest.pages.prefix(3) {
                if isCancelled() { throw ComicError.cancelled }
                guard let data = try? archive.readEntry(at: page.archiveIndex) else { continue }
                if let jpeg = renderer.coverJPEG(from: data) { cover = jpeg; break }
            }
        }
        if isCancelled() { throw ComicError.cancelled }

        // 4. Commit: move into Books/<id>/. Clean up on any failure.
        progress(ImportProgress(phase: .finishing, fraction: nil))
        let id = UUID()
        let dir = paths.bookDir(id)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try fm.moveItem(at: staged, to: paths.archiveFile(id, format: manifest.format))
            try PageManifestStore.write(manifest, to: paths.manifestFile(id))
            if let cover { try cover.write(to: paths.coverFile(id), options: .atomic) }
        } catch {
            try? fm.removeItem(at: dir)
            throw (error as? ComicError) ?? ComicError.ioError(detail: error.localizedDescription)
        }

        let original = source.lastPathComponent
        let baseName = (original as NSString).deletingPathExtension
        var record = BookRecord(id: id, displayName: BookImporter.uniqueName(baseName.isEmpty ? original : baseName,
                                                                             existing: existing.map(\.displayName)),
                                originalFileName: original, format: manifest.format, isSolid: manifest.isSolid,
                                fileSize: Int64(size), pageCount: manifest.pageCount, fingerprint: fingerprint,
                                hasCover: cover != nil, metadata: metadata)
        if metadata?.prefersRightToLeft == true { record.readingDirection = .rightToLeft }
        return .imported(record)
    }

    static func uniqueName(_ base: String, existing: [String]) -> String {
        let taken = Set(existing)
        if !taken.contains(base) { return base }
        var n = 2
        while taken.contains("\(base) (\(n))") { n += 1 }
        return "\(base) (\(n))"
    }

    /// Brings the file into the staging area and fingerprints it in constant memory:
    /// one buffer is reused for the whole file, so a 3 GB book needs no more RAM than a
    /// 30 MB one. On the same volume the "copy" is an APFS clone, which is instant and
    /// takes no extra space until one of the two files changes.
    private func stageFile(from source: URL, to dest: URL, progress: (ImportProgress) -> Void,
                           isCancelled: () -> Bool) throws -> (UInt64, UInt32) {
        let input = try RandomAccessFile(url: source)
        let total = input.size
        guard total <= limits.maxFileSize else { throw ComicError.archiveTooLarge(size: total, limit: limits.maxFileSize) }

        let reader: RandomAccessFile
        var output: Int32 = -1
        defer { if output >= 0 { close(output) } }
        if BookImporter.clone(source, to: dest, allowed: allowsCloning) {
            reader = try RandomAccessFile(url: dest)
        } else {
            // The copy plus room for solid-RAR extraction later is checked separately.
            try DiskSpacePolicy.check(required: Int64(total), at: paths.root, provider: diskSpace)
            reader = input
            output = dest.withUnsafeFileSystemRepresentation { path in
                path.map { open($0, O_WRONLY | O_CREAT | O_TRUNC, 0o644) } ?? -1
            }
            guard output >= 0 else { throw ComicError.ioError(detail: "cannot create staging file") }
        }

        let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: 1 << 20, alignment: 16)
        defer { buffer.deallocate() }
        var crc = CRC32()
        var done: UInt64 = 0
        var lastReport = Date.distantPast
        while true {
            if isCancelled() { throw ComicError.cancelled }
            let count: Int
            do { count = try reader.read(at: done, into: buffer) }
            catch { throw ComicError.sourceUnreadable(detail: "\(error)") }
            if count == 0 { break }
            let chunk = UnsafeRawBufferPointer(rebasing: buffer[..<count])
            crc.update(chunk)
            if output >= 0 { try writeAll(chunk, to: output, total: total) }
            done += UInt64(count)
            if Date().timeIntervalSince(lastReport) > 0.1 {
                lastReport = Date()
                progress(ImportProgress(phase: .copying, fraction: total > 0 ? Double(done) / Double(total) : nil))
            }
        }
        progress(ImportProgress(phase: .copying, fraction: 1))
        return (done, crc.value)
    }

    private func writeAll(_ bytes: UnsafeRawBufferPointer, to fd: Int32, total: UInt64) throws {
        var written = 0
        while written < bytes.count {
            let n = write(fd, bytes.baseAddress! + written, bytes.count - written)
            if n >= 0 { written += n; continue }
            if errno == EINTR { continue }
            if errno == ENOSPC {
                throw ComicError.insufficientDiskSpace(required: Int64(total), available: diskSpace.availableCapacity(for: paths.root) ?? 0)
            }
            throw ComicError.ioError(detail: String(cString: strerror(errno)))
        }
    }

    /// False when the file cannot be cloned (another volume, a file that is not local yet…),
    /// which is normal: the caller then copies it.
    private static func clone(_ source: URL, to dest: URL, allowed: Bool) -> Bool {
        #if canImport(Darwin)
        guard allowed else { return false }
        return source.withUnsafeFileSystemRepresentation { from in
            dest.withUnsafeFileSystemRepresentation { to in
                guard let from, let to else { return false }
                return clonefile(from, to, UInt32(CLONE_NOOWNERCOPY)) == 0
            }
        }
        #else
        return false
        #endif
    }
}

public enum PageManifestStore {
    public static func write(_ m: PageManifest, to url: URL) throws {
        try LibraryDatabase.encoder().encode(m).write(to: url, options: .atomic)
    }

    public static func read(_ url: URL) throws -> PageManifest {
        try LibraryDatabase.decoder().decode(PageManifest.self, from: Data(contentsOf: url))
    }
}
