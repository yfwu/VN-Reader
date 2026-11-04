import Foundation

/// Every failure the core can report. The app maps these to localized,
/// actionable messages (see `ErrorMessages.swift` in the app target), so
/// cases describe *what was actually observed*, never a generic "corrupt".
public enum ComicError: Error, Equatable, Sendable {
    /// The source file could not be read (permission, I/O, File Provider failure).
    case sourceUnreadable(detail: String)
    /// Magic bytes do not match ZIP or RAR. `detected` names what it looks like, if known (e.g. "PDF").
    case notAnArchive(detected: String?)
    /// A known archive type that this version cannot open (e.g. "7z", "TAR", "GZIP").
    case unsupportedArchiveType(String)
    /// Archive (or its file list) is password protected.
    case encryptedArchive
    /// The archive is one part of a multi-volume / spanned set.
    case multiVolumeArchive
    /// Entries use a compression method we do not implement (e.g. "BZIP2").
    case unsupportedCompression(method: String)
    /// The archive structure ends early (incomplete download / truncated copy).
    case truncatedArchive
    /// The archive structure is invalid at a specific place.
    case corruptArchive(detail: String)
    /// Data failed checksum verification while decompressing.
    case checksumMismatch(entry: String)
    /// No page images were found (after filtering non-page files).
    case noImages
    case tooManyEntries(count: Int, limit: Int)
    case entryTooLarge(entry: String, size: UInt64, limit: UInt64)
    case archiveTooLarge(size: UInt64, limit: UInt64)
    case insufficientDiskSpace(required: Int64, available: Int64)
    /// A single entry is password protected.
    case encryptedEntry(entry: String)
    case entryNotFound(index: Int)
    case cancelled
    case ioError(detail: String)
    /// RAR dictionary larger than the safe limit for this device.
    case dictionaryTooLarge
}

extension ComicError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .sourceUnreadable(let d): return "sourceUnreadable(\(d))"
        case .notAnArchive(let d): return "notAnArchive(\(d ?? "unknown"))"
        case .unsupportedArchiveType(let t): return "unsupportedArchiveType(\(t))"
        case .encryptedArchive: return "encryptedArchive"
        case .multiVolumeArchive: return "multiVolumeArchive"
        case .unsupportedCompression(let m): return "unsupportedCompression(\(m))"
        case .truncatedArchive: return "truncatedArchive"
        case .corruptArchive(let d): return "corruptArchive(\(d))"
        case .checksumMismatch(let e): return "checksumMismatch(\(e))"
        case .noImages: return "noImages"
        case .tooManyEntries(let c, let l): return "tooManyEntries(\(c)/\(l))"
        case .entryTooLarge(let e, let s, let l): return "entryTooLarge(\(e), \(s)/\(l))"
        case .archiveTooLarge(let s, let l): return "archiveTooLarge(\(s)/\(l))"
        case .insufficientDiskSpace(let r, let a): return "insufficientDiskSpace(required: \(r), available: \(a))"
        case .encryptedEntry(let e): return "encryptedEntry(\(e))"
        case .entryNotFound(let i): return "entryNotFound(\(i))"
        case .cancelled: return "cancelled"
        case .ioError(let d): return "ioError(\(d))"
        case .dictionaryTooLarge: return "dictionaryTooLarge"
        }
    }
}
