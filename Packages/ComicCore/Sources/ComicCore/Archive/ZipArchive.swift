import Foundation

/// ZIP reader with true random access via the central directory.
/// Supports stored and deflated entries, ZIP64 and legacy name encodings.
public final class ZipArchive: ComicArchive, @unchecked Sendable {
    public let format: ArchiveFormat = .zip
    public let supportsRandomAccess = true
    public let isSolid = false
    public private(set) var entries: [ArchiveEntry] = []

    private let file: RandomAccessFile
    private let limits: ArchiveLimits
    private var locations: [EntryLocation] = []

    struct EntryLocation {
        var localHeaderOffset: UInt64
        var method: UInt16
        var flags: UInt16
    }

    public init(url: URL, limits: ArchiveLimits = .default) throws {
        self.file = try RandomAccessFile(url: url)
        self.limits = limits
        try parseCentralDirectory()
    }

    // MARK: - Central directory

    private func parseCentralDirectory() throws {
        let size = file.size
        guard size >= 22 else { throw ComicError.truncatedArchive }
        let tailLength = Int(min(size, 22 + 65_535 + 20))
        let tailStart = size - UInt64(tailLength)
        let tail = try file.read(at: tailStart, count: tailLength)

        var eocd: Int? = nil
        var i = tail.count - 22
        while i >= 0 {
            if tail[i] == 0x50, tail[i + 1] == 0x4B, tail[i + 2] == 0x05, tail[i + 3] == 0x06 {
                eocd = i
                break
            }
            i -= 1
        }
        guard let e = eocd else {
            // Starts like a ZIP but has no end record: the copy is incomplete.
            throw ComicError.truncatedArchive
        }
        let diskNumber = tail.u16(e + 4)
        let cdDisk = tail.u16(e + 6)
        var entryCount = UInt64(tail.u16(e + 10))
        var cdSize = UInt64(tail.u32(e + 12))
        var cdOffset = UInt64(tail.u32(e + 16))
        let eocdAbs = tailStart + UInt64(e)

        var isZip64 = false
        if entryCount == 0xFFFF || cdSize == 0xFFFF_FFFF || cdOffset == 0xFFFF_FFFF, e >= 20,
           tail.u32(e - 20) == 0x0706_4B50 {
            let z64Offset = tail.u64(e - 20 + 8)
            let rec = try file.read(at: z64Offset, count: 56)
            guard rec.u32(0) == 0x0606_4B50 else { throw ComicError.corruptArchive(detail: "ZIP64 end record") }
            entryCount = rec.u64(32)
            cdSize = rec.u64(40)
            cdOffset = rec.u64(48)
            isZip64 = true
        } else if diskNumber != 0 || cdDisk != 0 {
            throw ComicError.multiVolumeArchive
        }

        // Tolerate data prepended to the archive (self-extractor stubs).
        var shift: UInt64 = 0
        if !isZip64, eocdAbs >= cdSize, eocdAbs - cdSize > cdOffset {
            shift = eocdAbs - cdSize - cdOffset
        }
        let cdStart = cdOffset + shift
        guard cdStart <= size, cdSize <= size - cdStart else { throw ComicError.truncatedArchive }
        guard entryCount <= UInt64(limits.maxEntries) else {
            throw ComicError.tooManyEntries(count: Int(clamping: entryCount), limit: limits.maxEntries)
        }
        guard cdSize <= 64 * 1024 * 1024 else { throw ComicError.corruptArchive(detail: "central directory too large") }
        let cd = try file.read(at: cdStart, count: Int(cdSize))

        struct Raw { var name: Data; var utf8: Bool; var unicodeExtra: String?; var e: ArchiveEntry; var loc: EntryLocation }
        var raws: [Raw] = []
        raws.reserveCapacity(Int(entryCount))
        var p = 0
        for n in 0..<Int(entryCount) {
            guard p + 46 <= cd.count, cd.u32(p) == 0x0201_4B50 else {
                throw ComicError.corruptArchive(detail: "central directory entry \(n)")
            }
            let flags = cd.u16(p + 8)
            let method = cd.u16(p + 10)
            let crc = cd.u32(p + 16)
            var compSize = UInt64(cd.u32(p + 20))
            var uncompSize = UInt64(cd.u32(p + 24))
            let nameLen = Int(cd.u16(p + 28))
            let extraLen = Int(cd.u16(p + 30))
            let commentLen = Int(cd.u16(p + 32))
            let externalAttr = cd.u32(p + 38)
            var localOffset = UInt64(cd.u32(p + 42))
            let nameStart = p + 46
            guard nameStart + nameLen + extraLen + commentLen <= cd.count else {
                throw ComicError.corruptArchive(detail: "central directory entry \(n) length")
            }
            let nameData = cd.subdata(in: (cd.startIndex + nameStart)..<(cd.startIndex + nameStart + nameLen))
            var unicodePath: String? = nil

            // Extra fields: ZIP64 sizes (0x0001), Info-ZIP Unicode path (0x7075).
            var x = nameStart + nameLen
            let xEnd = x + extraLen
            while x + 4 <= xEnd {
                let id = cd.u16(x)
                let len = Int(cd.u16(x + 2))
                let body = x + 4
                guard body + len <= xEnd else { break }
                if id == 0x0001 {
                    var q = body
                    if uncompSize == 0xFFFF_FFFF, q + 8 <= body + len { uncompSize = cd.u64(q); q += 8 }
                    if compSize == 0xFFFF_FFFF, q + 8 <= body + len { compSize = cd.u64(q); q += 8 }
                    if localOffset == 0xFFFF_FFFF, q + 8 <= body + len { localOffset = cd.u64(q); q += 8 }
                } else if id == 0x7075, len > 5 {
                    let storedCRC = cd.u32(body + 1)
                    if storedCRC == CRC32.checksum(nameData) {
                        let u = cd.subdata(in: (cd.startIndex + body + 5)..<(cd.startIndex + body + len))
                        unicodePath = String(data: u, encoding: .utf8)
                    }
                }
                x = body + len
            }

            let encrypted = flags & 0x1 != 0 || method == 99
            let unsupported: String?
            switch method {
            case 0, 8: unsupported = nil
            case 99: unsupported = nil // AES: reported as encryption instead
            default: unsupported = ZipArchive.methodName(method)
            }
            let isDir = nameData.last == UInt8(ascii: "/") || (externalAttr >> 16) & 0o170000 == 0o040000 && uncompSize == 0
            let entry = ArchiveEntry(index: n, path: "", uncompressedSize: uncompSize, compressedSize: compSize,
                                     isDirectory: isDir, isEncrypted: encrypted, unsupportedMethod: unsupported, crc32: crc)
            raws.append(Raw(name: nameData, utf8: flags & 0x800 != 0, unicodeExtra: unicodePath, e: entry,
                            loc: EntryLocation(localHeaderOffset: localOffset + shift, method: method, flags: flags)))
            p = nameStart + nameLen + extraLen + commentLen
        }

        let legacy = raws.filter { !$0.utf8 && $0.unicodeExtra == nil }.map { $0.name }
        let legacyEncoding = ZipNameDecoder.chooseEncoding(for: legacy)
        entries = raws.map { r in
            var e = r.e
            let name: String
            if let u = r.unicodeExtra { name = u }
            else if r.utf8 { name = String(decoding: r.name, as: UTF8.self) }
            else { name = String(data: r.name, encoding: legacyEncoding) ?? String(decoding: r.name, as: UTF8.self) }
            e.path = name.replacingOccurrences(of: "\\", with: "/")
            return e
        }
        locations = raws.map { $0.loc }
    }

    static func methodName(_ m: UInt16) -> String {
        switch m {
        case 1...7: return "Shrink/Reduce/Implode (\(m))"
        case 9: return "Deflate64"
        case 12: return "BZIP2"
        case 14: return "LZMA"
        case 93: return "Zstandard"
        case 95: return "XZ"
        case 96: return "JPEG (WinZip)"
        case 97: return "WavPack"
        case 98: return "PPMd"
        default: return "method \(m)"
        }
    }

    // MARK: - Reading

    public func readEntry(at index: Int) throws -> Data {
        guard entries.indices.contains(index) else { throw ComicError.entryNotFound(index: index) }
        let e = entries[index]
        let loc = locations[index]
        if e.isEncrypted { throw ComicError.encryptedEntry(entry: e.path) }
        if let m = e.unsupportedMethod { throw ComicError.unsupportedCompression(method: m) }
        guard e.uncompressedSize <= limits.maxEntrySize else {
            throw ComicError.entryTooLarge(entry: e.path, size: e.uncompressedSize, limit: limits.maxEntrySize)
        }
        let header = try file.read(at: loc.localHeaderOffset, count: 30)
        guard header.u32(0) == 0x0403_4B50 else {
            throw ComicError.corruptArchive(detail: "local header of \(e.path)")
        }
        let dataStart = loc.localHeaderOffset + 30 + UInt64(header.u16(26)) + UInt64(header.u16(28))
        guard e.compressedSize <= limits.maxEntrySize else {
            throw ComicError.entryTooLarge(entry: e.path, size: e.compressedSize, limit: limits.maxEntrySize)
        }
        let compressed = try file.read(at: dataStart, count: Int(e.compressedSize))
        let data: Data
        switch loc.method {
        case 0:
            data = compressed
        case 8:
            data = try Inflate.rawInflate(compressed, expectedSize: e.uncompressedSize,
                                          maxOutput: limits.maxEntrySize, entryName: e.path)
        default:
            throw ComicError.unsupportedCompression(method: ZipArchive.methodName(loc.method))
        }
        if UInt64(data.count) != e.uncompressedSize || CRC32.checksum(data) != e.crc32 {
            throw ComicError.checksumMismatch(entry: e.path)
        }
        return data
    }

    public func extractSequentially(indices: Set<Int>, handler: (Int, Data) throws -> Bool) throws {
        for i in indices.sorted() {
            if try !handler(i, try readEntry(at: i)) { return }
        }
    }
}
