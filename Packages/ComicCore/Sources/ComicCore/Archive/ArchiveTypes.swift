import Foundation

public enum ArchiveFormat: String, Codable, Sendable, CaseIterable {
    case zip
    case rar4
    case rar5

    public var isRAR: Bool { self != .zip }
    /// File extension used for the app-managed copy.
    public var managedExtension: String { self == .zip ? "cbz" : "cbr" }
}

/// One file inside an archive, in archive (physical) order.
public struct ArchiveEntry: Hashable, Codable, Sendable {
    /// Position of the entry in archive order (0-based). Stable for a given file.
    public var index: Int
    /// Decoded path, '/' separated.
    public var path: String
    public var uncompressedSize: UInt64
    public var compressedSize: UInt64
    public var isDirectory: Bool
    public var isEncrypted: Bool
    /// Human readable method name when the method is not supported; nil if supported.
    public var unsupportedMethod: String?
    public var crc32: UInt32

    public init(index: Int, path: String, uncompressedSize: UInt64, compressedSize: UInt64,
                isDirectory: Bool, isEncrypted: Bool, unsupportedMethod: String? = nil, crc32: UInt32 = 0) {
        self.index = index
        self.path = path
        self.uncompressedSize = uncompressedSize
        self.compressedSize = compressedSize
        self.isDirectory = isDirectory
        self.isEncrypted = isEncrypted
        self.unsupportedMethod = unsupportedMethod
        self.crc32 = crc32
    }
}

/// Safety limits applied when listing and decompressing.
public struct ArchiveLimits: Sendable {
    public var maxEntries: Int
    /// Largest single entry we will decompress into memory.
    public var maxEntrySize: UInt64

    public init(maxEntries: Int = 20_000, maxEntrySize: UInt64 = 256 * 1024 * 1024) {
        self.maxEntries = maxEntries
        self.maxEntrySize = maxEntrySize
    }

    public static let `default` = ArchiveLimits()
}

/// Read access to a comic archive. Implementations are thread safe.
public protocol ComicArchive: AnyObject, Sendable {
    var format: ArchiveFormat { get }
    var entries: [ArchiveEntry] { get }
    /// True when reading an arbitrary entry is cheap. False for solid RAR,
    /// where entry N can only be produced after decompressing entries 0..<N.
    var supportsRandomAccess: Bool { get }
    var isSolid: Bool { get }

    /// Decompresses one entry fully into memory (bounded by limits).
    func readEntry(at index: Int) throws -> Data

    /// Decompresses entries in archive order and delivers those in `indices`.
    /// `handler` returns false to stop early (e.g. cancellation).
    func extractSequentially(indices: Set<Int>, handler: (Int, Data) throws -> Bool) throws
}
