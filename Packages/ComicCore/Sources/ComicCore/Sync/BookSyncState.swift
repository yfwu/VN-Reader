import Foundation

/// A total, deterministic timestamp. Receiving remote stamps before the next local
/// edit keeps edits ordered even when the wall clock moves backwards.
public struct SyncStamp: Codable, Equatable, Comparable, Sendable {
    public var milliseconds: Int64
    public var counter: UInt64
    public var device: String
    public init(milliseconds: Int64, counter: UInt64 = 0, device: String) {
        self.milliseconds = milliseconds; self.counter = counter; self.device = device
    }
    public static func < (a: Self, b: Self) -> Bool {
        if a.milliseconds != b.milliseconds { return a.milliseconds < b.milliseconds }
        if a.counter != b.counter { return a.counter < b.counter }
        return a.device < b.device
    }
}

public struct SyncRegister: Codable, Equatable, Sendable {
    public var value: String?
    public var stamp: SyncStamp
    public init(value: String?, stamp: SyncStamp) { self.value = value; self.stamp = stamp }
    /// The value tie-break also makes malformed equal-stamp records converge.
    public func merged(with other: Self) -> Self {
        if stamp != other.stamp { return stamp > other.stamp ? self : other }
        if value == other.value { return self }
        if value == nil { return other }
        if other.value == nil { return self }
        return value! > other.value! ? self : other
    }
}

/// Only logical state is synchronized. Local IDs, download state, fit and layout
/// remain device-local. Archive SHA-256 identifies the immutable file revision.
public struct BookSyncState: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public var version: Int = currentVersion
    public var contentID: String
    public var fields: [String: SyncRegister]

    public init(contentID: String, book: BookRecord, device: String) {
        self.contentID = contentID
        let stamp = SyncStamp(milliseconds: 0, device: "")
        fields = Self.values(book).mapValues { SyncRegister(value: $0, stamp: stamp) }
        for p in book.bookmarks { fields["bookmark.\(p)"] = SyncRegister(value: "1", stamp: stamp) }
        // Existing reading activity wins over a never-read duplicate on another device.
        if let date = book.progress.lastReadAt {
            fields["progress"]?.stamp.milliseconds = Int64(date.timeIntervalSince1970 * 1000)
        }
    }

    public static func validContentID(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    /// Captures only actual edits, including explicit clears and removed bookmarks.
    public mutating func capture(_ book: BookRecord, device: String, now: Date = Date()) {
        var desired = Self.values(book)
        let bookmarks = Set(book.bookmarks)
        let known = fields.keys.filter { $0.hasPrefix("bookmark.") }
        for key in known { desired[key] = bookmarks.contains(Int(key.dropFirst(9)) ?? -1) ? "1" : "0" }
        for p in bookmarks { desired["bookmark.\(p)"] = "1" }
        let changed = desired.filter { fields[$0.key]?.value != $0.value }
        guard !changed.isEmpty else { return }
        let latest = fields.values.map(\.stamp).max() ?? SyncStamp(milliseconds: 0, device: device)
        let nowMS = Int64(now.timeIntervalSince1970 * 1000)
        let rollover = latest.counter >= UInt64.max - 1 && nowMS <= latest.milliseconds
        let stamp = SyncStamp(milliseconds: max(nowMS, latest.milliseconds) + (rollover ? 1 : 0),
                              counter: nowMS > latest.milliseconds || rollover ? 0 : latest.counter + 1, device: device)
        for (key, value) in changed { fields[key] = SyncRegister(value: value, stamp: stamp) }
    }

    public func merged(with other: Self) -> Self {
        precondition(contentID == other.contentID && version == other.version)
        var result = self
        for (key, value) in other.fields {
            result.fields[key] = result.fields[key]?.merged(with: value) ?? value
        }
        return result
    }

    /// An incoming event can arrive before a coalesced local save. Preserve those
    /// in-memory edits by assigning stamps before the remote registers are merged.
    public func mergedPreservingPendingChanges(with remote: Self, localBook: BookRecord, device: String, now: Date = Date()) -> Self {
        var local = self
        local.capture(localBook, device: device, now: now)
        return local.merged(with: remote)
    }

    public func apply(to book: inout BookRecord) {
        if let name = fields["name"]?.value, !name.isEmpty { book.displayName = name }
        var metadata = book.metadata ?? ComicMetadata()
        for field in MetadataField.allCases {
            if let register = fields["metadata.\(field.rawValue)"] { metadata[field] = register.value }
        }
        book.metadata = metadata == ComicMetadata() ? nil : metadata
        if let value = fields["favorite"]?.value { book.isFavorite = value == "1" }
        if let value = fields["direction"]?.value, let direction = ReadingDirection(rawValue: value) { book.readingDirection = direction }
        if let value = fields["progress"]?.value, let data = value.data(using: .utf8),
           var p = try? JSONDecoder().decode(ReadingProgress.self, from: data) {
            p.currentPage = max(0, min(p.currentPage, max(0, book.pageCount - 1)))
            book.progress = p
        }
        book.bookmarks = fields.compactMap { key, value -> Int? in
            guard key.hasPrefix("bookmark."), value.value == "1", let page = Int(key.dropFirst(9)),
                  page >= 0, page < book.pageCount else { return nil }
            return page
        }.sorted()
        book.syncState = self
    }

    private static func values(_ book: BookRecord) -> [String: String?] {
        var result: [String: String?] = ["name": book.displayName, "favorite": book.isFavorite ? "1" : "0",
                                        "direction": book.readingDirection.rawValue]
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        var progress = book.progress
        if let date = progress.lastReadAt { progress.lastReadAt = Date(timeIntervalSince1970: floor(date.timeIntervalSince1970)) }
        result["progress"] = try? String(data: encoder.encode(progress), encoding: .utf8)
        for f in MetadataField.allCases { result["metadata.\(f.rawValue)"] = .some(book.metadata?[f]) }
        return result
    }
}

/// Immutable facts for rendering a remote-only book before downloading its archive.
public struct CloudBookEnvelope: Codable, Equatable, Sendable {
    public var state: BookSyncState
    public var originalFileName: String
    public var format: ArchiveFormat
    public var isSolid: Bool
    public var fileSize: Int64
    public var pageCount: Int
    public var importedAt: Date
    public var fingerprint: String
    public var hasCover: Bool

    public init(book: BookRecord, state: BookSyncState) {
        self.state = state; originalFileName = book.originalFileName; format = book.format
        isSolid = book.isSolid; fileSize = book.fileSize; pageCount = book.pageCount
        importedAt = book.importedAt; fingerprint = book.fingerprint; hasCover = book.hasCover
    }

    public var isValid: Bool {
        state.version == BookSyncState.currentVersion && BookSyncState.validContentID(state.contentID)
            && fileSize > 0 && fileSize <= 8 * 1024 * 1024 * 1024 && pageCount > 0 && pageCount <= 10_000
            && state.fields.count <= 10_100 && originalFileName.utf8.count <= 4096
            && state.fields.allSatisfy { key, value in
                key.utf8.count <= 128 && (value.value?.utf8.count ?? 0) <= 100_000
                    && value.stamp.milliseconds >= 0 && value.stamp.milliseconds <= 253_402_300_799_000
                    && value.stamp.counter < UInt64.max && value.stamp.device.utf8.count <= 128
            }
    }

    public func localRecord(account: String) -> BookRecord {
        var book = BookRecord(displayName: originalFileName, originalFileName: originalFileName, format: format,
                              isSolid: isSolid, fileSize: fileSize, pageCount: pageCount, importedAt: importedAt,
                              fingerprint: fingerprint, hasCover: hasCover)
        state.apply(to: &book)
        book.syncAccountID = account
        return book
    }
}
