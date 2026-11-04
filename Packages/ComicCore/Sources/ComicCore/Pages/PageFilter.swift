import Foundation

public enum ImageFileType: String, Codable, Sendable, CaseIterable {
    case jpeg, png, webp, gif, heic, avif, bmp, tiff

    public static func from(path: String) -> ImageFileType? {
        guard let dot = path.lastIndex(of: ".") else { return nil }
        switch path[path.index(after: dot)...].lowercased() {
        case "jpg", "jpeg", "jpe", "jfif": return .jpeg
        case "png": return .png
        case "webp": return .webp
        case "gif": return .gif
        case "heic", "heif": return .heic
        case "avif": return .avif
        case "bmp": return .bmp
        case "tif", "tiff": return .tiff
        default: return nil
        }
    }
}

/// Decides which archive entries are pages.
public enum PageFilter {
    public enum Verdict: Equatable { case page(ImageFileType), ignoredSystemFile, ignoredNonImage, directory }

    public static func classify(_ entry: ArchiveEntry) -> Verdict {
        if entry.isDirectory { return .directory }
        if isSystemFile(entry.path) { return .ignoredSystemFile }
        guard let type = ImageFileType.from(path: entry.path) else { return .ignoredNonImage }
        if entry.uncompressedSize == 0 { return .ignoredNonImage }
        return .page(type)
    }

    /// macOS resource forks, Finder / Explorer metadata and hidden files.
    public static func isSystemFile(_ path: String) -> Bool {
        let parts = path.split(separator: "/")
        guard let name = parts.last else { return true }
        for dir in parts.dropLast() {
            if dir == "__MACOSX" || (dir.hasPrefix(".") && dir != "." && dir != "..") { return true }
        }
        let lower = name.lowercased()
        if name.hasPrefix("._") || name.hasPrefix(".") { return true }   // AppleDouble, .DS_Store, dotfiles
        if lower == "thumbs.db" || lower == "desktop.ini" { return true }
        return false
    }
}
