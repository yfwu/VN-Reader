import Foundation

public enum ArchiveOpener {
    /// Opens an archive after identifying it by content (not by extension).
    public static func open(url: URL, limits: ArchiveLimits = .default) throws -> ComicArchive {
        switch try FormatDetector.detect(fileAt: url) {
        case .archive(.zip): return try ZipArchive(url: url, limits: limits)
        case .archive(let f): return try RarArchive(url: url, format: f, limits: limits)
        case .unsupportedArchive(let t): throw ComicError.unsupportedArchiveType(t)
        case .otherDocument(let d): throw ComicError.notAnArchive(detected: d)
        case .unknown: throw ComicError.notAnArchive(detected: nil)
        }
    }
}
