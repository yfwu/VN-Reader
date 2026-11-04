import Foundation
import CUnrar

/// RAR4 / RAR5 reader backed by RARLAB's unrar library.
///
/// unrar keeps some process-wide state (error handler), so every call into it
/// is serialised through `RarArchive.lock`.
public final class RarArchive: ComicArchive, @unchecked Sendable {
    public let format: ArchiveFormat
    public private(set) var entries: [ArchiveEntry] = []
    public let isSolid: Bool
    public var supportsRandomAccess: Bool { !isSolid }
    public let isMultiVolume: Bool

    static let lock = NSRecursiveLock()

    private let path: String
    private let limits: ArchiveLimits
    /// An extraction-mode handle positioned before entry `cursorNext`.
    private var cursor: OpaquePointer?
    private var cursorNext = 0

    public init(url: URL, format: ArchiveFormat, limits: ArchiveLimits = .default) throws {
        self.path = url.path
        self.format = format
        self.limits = limits
        RarArchive.lock.lock()
        defer { RarArchive.lock.unlock() }

        var handle: OpaquePointer?
        var flags: UInt32 = 0
        let rc = vnrar_open(path, 1, &handle, &flags)
        guard rc == VNRAR_OK, let h = handle else { throw RarArchive.mapError(rc, entry: nil) }
        defer { vnrar_close(h) }
        if flags & UInt32(VNRAR_ARC_ENCHEADERS) != 0 { throw ComicError.encryptedArchive }
        isSolid = flags & UInt32(VNRAR_ARC_SOLID) != 0
        isMultiVolume = flags & UInt32(VNRAR_ARC_VOLUME) != 0

        var list: [ArchiveEntry] = []
        var raw = VNRarEntry()
        while true {
            let r = vnrar_next(h, &raw)
            if r == VNRAR_END { break }
            if r == VNRAR_NEEDS_VOLUME { throw ComicError.multiVolumeArchive }
            guard r == VNRAR_OK else { throw RarArchive.mapError(r, entry: nil) }
            let name = withUnsafeBytes(of: &raw.name) { buf in
                String(decoding: buf.prefix(while: { $0 != 0 }), as: UTF8.self)
            }
            let f = raw.flags
            if f & UInt32(VNRAR_ENTRY_SPLITBEFORE | VNRAR_ENTRY_SPLITAFTER) != 0 {
                throw ComicError.multiVolumeArchive
            }
            list.append(ArchiveEntry(
                index: list.count, path: name,
                uncompressedSize: raw.unpackedSize, compressedSize: raw.packedSize,
                isDirectory: f & UInt32(VNRAR_ENTRY_DIRECTORY) != 0 || raw.redirType != 0,
                isEncrypted: f & UInt32(VNRAR_ENTRY_ENCRYPTED) != 0,
                unsupportedMethod: nil, crc32: raw.crc32))
            guard list.count <= limits.maxEntries else {
                throw ComicError.tooManyEntries(count: list.count, limit: limits.maxEntries)
            }
            let s = vnrar_skip(h)
            if s == VNRAR_NEEDS_VOLUME { throw ComicError.multiVolumeArchive }
            guard s == VNRAR_OK else { throw RarArchive.mapError(s, entry: name) }
        }
        if isMultiVolume { throw ComicError.multiVolumeArchive }
        entries = list
    }

    deinit {
        RarArchive.lock.lock()
        if let c = cursor { vnrar_close(c) }
        RarArchive.lock.unlock()
    }

    // MARK: - Reading

    private final class Sink {
        var data = Data()
        let limit: UInt64
        var overflow = false
        init(expected: UInt64, limit: UInt64) {
            self.limit = limit
            data.reserveCapacity(Int(min(expected, limit)))
        }
    }

    private static let sinkCallback: vnrar_data_callback = { bytes, length, ctx in
        let sink = Unmanaged<Sink>.fromOpaque(ctx!).takeUnretainedValue()
        if UInt64(sink.data.count) + UInt64(length) > sink.limit {
            sink.overflow = true
            return 1
        }
        if let bytes, length > 0 { sink.data.append(bytes, count: length) }
        return 0
    }

    private func openCursor() throws {
        if let c = cursor { vnrar_close(c) }
        cursor = nil
        var handle: OpaquePointer?
        let rc = vnrar_open(path, 0, &handle, nil)
        guard rc == VNRAR_OK, let h = handle else { throw RarArchive.mapError(rc, entry: nil) }
        cursor = h
        cursorNext = 0
    }

    /// Moves the cursor to just before `index` (re-opening if it is behind).
    private func seekCursor(to index: Int) throws {
        if cursor == nil || cursorNext > index { try openCursor() }
        var raw = VNRarEntry()
        while cursorNext < index {
            let r = vnrar_next(cursor, &raw)
            guard r == VNRAR_OK else { invalidateCursor(); throw RarArchive.mapError(r, entry: nil) }
            let s = vnrar_skip(cursor)
            guard s == VNRAR_OK else { invalidateCursor(); throw RarArchive.mapError(s, entry: entries[cursorNext].path) }
            cursorNext += 1
        }
    }

    private func invalidateCursor() {
        if let c = cursor { vnrar_close(c) }
        cursor = nil
        cursorNext = 0
    }

    /// Reads the entry at the cursor (which must be positioned at `index`).
    private func readAtCursor(_ index: Int) throws -> Data {
        let e = entries[index]
        var raw = VNRarEntry()
        let r = vnrar_next(cursor, &raw)
        guard r == VNRAR_OK else { invalidateCursor(); throw RarArchive.mapError(r, entry: e.path) }
        let sink = Sink(expected: e.uncompressedSize, limit: limits.maxEntrySize)
        let ctx = Unmanaged.passUnretained(sink).toOpaque()
        let rc = vnrar_read(cursor, RarArchive.sinkCallback, ctx)
        cursorNext += 1
        if rc != VNRAR_OK {
            invalidateCursor()
            if sink.overflow {
                throw ComicError.entryTooLarge(entry: e.path, size: e.uncompressedSize, limit: limits.maxEntrySize)
            }
            throw RarArchive.mapError(rc, entry: e.path)
        }
        return sink.data
    }

    public func readEntry(at index: Int) throws -> Data {
        guard entries.indices.contains(index) else { throw ComicError.entryNotFound(index: index) }
        let e = entries[index]
        if e.isEncrypted { throw ComicError.encryptedEntry(entry: e.path) }
        guard e.uncompressedSize <= limits.maxEntrySize else {
            throw ComicError.entryTooLarge(entry: e.path, size: e.uncompressedSize, limit: limits.maxEntrySize)
        }
        RarArchive.lock.lock()
        defer { RarArchive.lock.unlock() }
        try seekCursor(to: index)
        return try readAtCursor(index)
    }

    public func extractSequentially(indices: Set<Int>, handler: (Int, Data) throws -> Bool) throws {
        guard let last = indices.max() else { return }
        var i = 0
        while i <= last {
            // Lock per entry so other readers (thumbnails) can interleave.
            let item: (Int, Data)? = try {
                RarArchive.lock.lock()
                defer { RarArchive.lock.unlock() }
                if cursor == nil || cursorNext != i { try seekCursor(to: i) }
                if indices.contains(i) {
                    let e = entries[i]
                    if e.isEncrypted { throw ComicError.encryptedEntry(entry: e.path) }
                    guard e.uncompressedSize <= limits.maxEntrySize else {
                        throw ComicError.entryTooLarge(entry: e.path, size: e.uncompressedSize, limit: limits.maxEntrySize)
                    }
                    return (i, try readAtCursor(i))
                } else {
                    try seekCursor(to: i + 1)
                    return nil
                }
            }()
            if let (idx, data) = item, try !handler(idx, data) { return }
            i += 1
        }
    }

    static func mapError(_ code: Int32, entry: String?) -> ComicError {
        switch Int(code) {
        case Int(VNRAR_MISSING_PASSWORD), Int(VNRAR_BAD_PASSWORD):
            return entry.map { .encryptedEntry(entry: $0) } ?? .encryptedArchive
        case Int(VNRAR_NEEDS_VOLUME): return .multiVolumeArchive
        case Int(VNRAR_BAD_DATA):
            return entry.map { .checksumMismatch(entry: $0) } ?? .corruptArchive(detail: "RAR header data")
        case Int(VNRAR_BAD_ARCHIVE): return .corruptArchive(detail: "not a valid RAR archive")
        case Int(VNRAR_UNKNOWN_FORMAT): return .unsupportedCompression(method: "unknown RAR format")
        case Int(VNRAR_EOPEN): return .sourceUnreadable(detail: "cannot open RAR file")
        case Int(VNRAR_EREAD): return .truncatedArchive
        case Int(VNRAR_NO_MEMORY): return .ioError(detail: "out of memory")
        case Int(VNRAR_LARGE_DICT): return .dictionaryTooLarge
        case Int(VNRAR_ABORTED): return .cancelled
        default: return .corruptArchive(detail: "unrar error \(code)")
        }
    }

    public static var unrarVersion: String {
        let v = Int(vnrar_unrar_version())
        return "\(v / 100).\(String(format: "%02d", v % 100))"
    }
}
