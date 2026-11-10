import Foundation

public enum ReadingDirection: String, Codable, Sendable, CaseIterable {
    case leftToRight
    case rightToLeft
}

public enum PageFitMode: String, Codable, Sendable, CaseIterable {
    /// Whole page visible (letter-boxed).
    case fitPage
    /// Page width fills the screen; tall pages scroll vertically.
    case fitWidth
}

public enum PageLayout: String, Codable, Sendable, CaseIterable {
    case single
    /// Two pages side by side (used in landscape when enabled).
    case double
    /// Continuous vertical scrolling.
    case vertical
}

public enum ReadingStatus: String, Codable, Sendable, CaseIterable {
    case unread, reading, finished
}

public struct ReadingProgress: Codable, Equatable, Sendable {
    /// Logical page index (0-based) into the frozen manifest.
    public var currentPage: Int = 0
    public var lastReadAt: Date?
    public var finished: Bool = false

    public init(currentPage: Int = 0, lastReadAt: Date? = nil, finished: Bool = false) {
        self.currentPage = currentPage
        self.lastReadAt = lastReadAt
        self.finished = finished
    }
}

public struct ComicMetadata: Codable, Equatable, Sendable {
    /// This book's own title (story or volume name), not the series.
    public var title: String?
    public var series: String?
    /// Position in the series: the issue for US comics, the volume for manga.
    public var number: String?
    /// ComicInfo "Volume": which run of a US series, usually its start year ("2016").
    public var volume: String?
    public var writer: String?
    public var penciller: String?
    public var publisher: String?
    public var year: Int?
    public var summary: String?
    /// ComicInfo "Manga" == "YesAndRightToLeft".
    public var prefersRightToLeft: Bool = false

    public init(title: String? = nil, series: String? = nil, number: String? = nil, volume: String? = nil,
                writer: String? = nil, penciller: String? = nil, publisher: String? = nil, year: Int? = nil,
                summary: String? = nil, prefersRightToLeft: Bool = false) {
        self.title = title
        self.series = series
        self.number = number
        self.volume = volume
        self.writer = writer
        self.penciller = penciller
        self.publisher = publisher
        self.year = year
        self.summary = summary
        self.prefersRightToLeft = prefersRightToLeft
    }
}

/// A fully imported, readable book. Only complete imports become records.
public struct BookRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var displayName: String
    public var originalFileName: String
    public var format: ArchiveFormat
    public var isSolid: Bool
    public var fileSize: Int64
    public var pageCount: Int
    public var importedAt: Date
    /// "crc32-size" of the archive file; used for duplicate detection.
    public var fingerprint: String
    public var hasCover: Bool

    public var progress: ReadingProgress
    public var readingDirection: ReadingDirection
    public var fitMode: PageFitMode
    public var layout: PageLayout

    // P1 fields — decoded with defaults so older libraries still load.
    public var bookmarks: [Int]
    public var isFavorite: Bool
    public var metadata: ComicMetadata?
    public var syncState: BookSyncState? = nil
    /// Local account binding. Never uploaded as part of the cloud payload.
    public var syncAccountID: String? = nil

    public init(id: UUID = UUID(), displayName: String, originalFileName: String, format: ArchiveFormat,
                isSolid: Bool, fileSize: Int64, pageCount: Int, importedAt: Date = Date(), fingerprint: String,
                hasCover: Bool, progress: ReadingProgress = ReadingProgress(),
                readingDirection: ReadingDirection = .leftToRight, fitMode: PageFitMode = .fitPage,
                layout: PageLayout = .single, bookmarks: [Int] = [], isFavorite: Bool = false,
                metadata: ComicMetadata? = nil) {
        self.id = id
        self.displayName = displayName
        self.originalFileName = originalFileName
        self.format = format
        self.isSolid = isSolid
        self.fileSize = fileSize
        self.pageCount = pageCount
        self.importedAt = importedAt
        self.fingerprint = fingerprint
        self.hasCover = hasCover
        self.progress = progress
        self.readingDirection = readingDirection
        self.fitMode = fitMode
        self.layout = layout
        self.bookmarks = bookmarks
        self.isFavorite = isFavorite
        self.metadata = metadata
    }

    enum CodingKeys: String, CodingKey {
        case id, displayName, originalFileName, format, isSolid, fileSize, pageCount, importedAt, fingerprint,
             hasCover, progress, readingDirection, fitMode, layout, bookmarks, isFavorite, metadata, syncState, syncAccountID
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        displayName = try c.decode(String.self, forKey: .displayName)
        originalFileName = try c.decode(String.self, forKey: .originalFileName)
        format = try c.decode(ArchiveFormat.self, forKey: .format)
        isSolid = try c.decodeIfPresent(Bool.self, forKey: .isSolid) ?? false
        fileSize = try c.decode(Int64.self, forKey: .fileSize)
        pageCount = try c.decode(Int.self, forKey: .pageCount)
        importedAt = try c.decode(Date.self, forKey: .importedAt)
        fingerprint = try c.decode(String.self, forKey: .fingerprint)
        hasCover = try c.decodeIfPresent(Bool.self, forKey: .hasCover) ?? false
        progress = try c.decodeIfPresent(ReadingProgress.self, forKey: .progress) ?? ReadingProgress()
        readingDirection = (try? c.decode(ReadingDirection.self, forKey: .readingDirection)) ?? .leftToRight
        fitMode = (try? c.decode(PageFitMode.self, forKey: .fitMode)) ?? .fitPage
        layout = (try? c.decode(PageLayout.self, forKey: .layout)) ?? .single
        bookmarks = try c.decodeIfPresent([Int].self, forKey: .bookmarks) ?? []
        isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        metadata = try c.decodeIfPresent(ComicMetadata.self, forKey: .metadata)
        syncState = try c.decodeIfPresent(BookSyncState.self, forKey: .syncState)
        syncAccountID = try c.decodeIfPresent(String.self, forKey: .syncAccountID)
    }

    public var status: ReadingStatus {
        if progress.finished { return .finished }
        if progress.lastReadAt == nil { return .unread }
        return .reading
    }

    /// 0...1 fraction for progress bars.
    public var progressFraction: Double {
        guard pageCount > 1 else { return progress.finished ? 1 : 0 }
        if progress.finished { return 1 }
        return Double(progress.currentPage) / Double(pageCount - 1)
    }

    /// Records reading position. Reaching the last page marks the book finished.
    public mutating func recordPosition(_ page: Int, at date: Date = Date()) {
        let clamped = max(0, min(page, pageCount - 1))
        progress.currentPage = clamped
        progress.lastReadAt = date
        if clamped >= pageCount - 1 { progress.finished = true }
    }

    public mutating func resetProgress() {
        progress = ReadingProgress()
    }
}
