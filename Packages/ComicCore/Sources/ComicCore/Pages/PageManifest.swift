import Foundation

public struct PageEntry: Codable, Hashable, Sendable {
    /// Index of the entry in archive order.
    public var archiveIndex: Int
    public var path: String
    public var size: UInt64
    public var type: ImageFileType
}

/// The frozen mapping from logical page number to archive entry.
///
/// Built once at import and stored next to the book, so page order never
/// changes when the book is reopened (even if sorting rules evolve).
public struct PageManifest: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public var version: Int
    public var format: ArchiveFormat
    public var isSolid: Bool
    public var pages: [PageEntry]
    public var ignoredEntryCount: Int
    /// Archive index of ComicInfo.xml, if present.
    public var comicInfoIndex: Int?

    public var pageCount: Int { pages.count }
    public var totalPageBytes: UInt64 { pages.reduce(0) { $0 + $1.size } }

    public static func build(from archive: ComicArchive) throws -> PageManifest {
        try build(entries: archive.entries, format: archive.format, isSolid: archive.isSolid)
    }

    public static func build(entries: [ArchiveEntry], format: ArchiveFormat, isSolid: Bool) throws -> PageManifest {
        var pages: [PageEntry] = []
        var ignored = 0
        var encryptedPages = 0
        var unsupported: String? = nil
        var comicInfo: Int? = nil
        for e in entries {
            if !e.isDirectory, e.path.split(separator: "/").last?.lowercased() == "comicinfo.xml",
               comicInfo == nil || !e.path.contains("/") {
                comicInfo = e.index
            }
            switch PageFilter.classify(e) {
            case .page(let t):
                if e.isEncrypted { encryptedPages += 1 }
                if let m = e.unsupportedMethod { unsupported = m }
                pages.append(PageEntry(archiveIndex: e.index, path: e.path, size: e.uncompressedSize, type: t))
            case .directory:
                break
            case .ignoredSystemFile, .ignoredNonImage:
                ignored += 1
            }
        }
        guard !pages.isEmpty else { throw ComicError.noImages }
        if encryptedPages == pages.count { throw ComicError.encryptedArchive }
        if let m = unsupported, pages.allSatisfy({ e in entries[e.archiveIndex].unsupportedMethod != nil }) {
            throw ComicError.unsupportedCompression(method: m)
        }
        pages.sort { a, b in
            let r = NaturalSort.comparePaths(a.path, b.path)
            return r == .orderedSame ? a.archiveIndex < b.archiveIndex : r == .orderedAscending
        }
        return PageManifest(version: currentVersion, format: format, isSolid: isSolid, pages: pages,
                            ignoredEntryCount: ignored, comicInfoIndex: comicInfo)
    }
}
