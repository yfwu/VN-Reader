import Foundation

public enum DetectedKind: Equatable, Sendable {
    case archive(ArchiveFormat)
    case unsupportedArchive(String)
    case otherDocument(String)
    case unknown
}

/// Identifies a file by its leading bytes; the file extension is never trusted.
public enum FormatDetector {
    public static let headerLength = 16

    public static func detect(header: Data) -> DetectedKind {
        let b = [UInt8](header.prefix(headerLength))
        func starts(_ sig: [UInt8]) -> Bool { b.count >= sig.count && Array(b[0..<sig.count]) == sig }

        if starts([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00]) { return .archive(.rar5) }
        if starts([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00]) { return .archive(.rar4) }
        // "PK\3\4" local header, "PK\5\6" empty archive, "PK\7\8" spanned marker.
        if starts([0x50, 0x4B, 0x03, 0x04]) || starts([0x50, 0x4B, 0x05, 0x06]) || starts([0x50, 0x4B, 0x07, 0x08]) {
            return .archive(.zip)
        }
        if starts([0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]) { return .unsupportedArchive("7z") }
        if starts([0x1F, 0x8B]) { return .unsupportedArchive("GZIP") }
        if starts([0x42, 0x5A, 0x68]) { return .unsupportedArchive("BZIP2") }
        if starts([0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]) { return .unsupportedArchive("XZ") }
        if starts([0x28, 0xB5, 0x2F, 0xFD]) { return .unsupportedArchive("Zstandard") }
        if starts(Array("%PDF".utf8)) { return .otherDocument("PDF") }
        if starts([0xFF, 0xD8, 0xFF]) { return .otherDocument("JPEG") }
        if starts([0x89, 0x50, 0x4E, 0x47]) { return .otherDocument("PNG") }
        return .unknown
    }

    public static func detect(fileAt url: URL) throws -> DetectedKind {
        let file = try RandomAccessFile(url: url)
        let n = min(Int(file.size), 512)
        let data = try file.read(at: 0, count: n)
        if detect(header: data) == .unknown, n >= 262 {
            // POSIX tar has "ustar" at offset 257.
            let magic = data.subdata(in: 257..<262)
            if magic == Data("ustar".utf8) { return .unsupportedArchive("TAR") }
        }
        return detect(header: data)
    }
}
