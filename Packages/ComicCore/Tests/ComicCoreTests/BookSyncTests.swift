import XCTest
@testable import ComicCore

final class BookSyncTests: XCTestCase {
    private let contentHash = String(repeating: "a", count: 64)
    private func book() -> BookRecord {
        BookRecord(displayName: "Test", originalFileName: "test.cbz", format: .zip, isSolid: false,
                   fileSize: 128, pageCount: 20, fingerprint: "abc", hasCover: false,
                   metadata: ComicMetadata(series: "Original", writer: "Writer"))
    }

    func testConcurrentDifferentFieldsMergeAndConverge() {
        let original = book()
        var a = BookSyncState(contentID: contentHash, book: original, device: "A")
        var b = a
        var left = original; left.metadata?.series = "New series"
        var right = original; right.metadata?.writer = "New writer"
        a.capture(left, device: "A", now: Date(timeIntervalSince1970: 100))
        b.capture(right, device: "B", now: Date(timeIntervalSince1970: 100))
        let merged = a.merged(with: b)
        XCTAssertEqual(merged, b.merged(with: a))
        XCTAssertEqual(merged, merged.merged(with: merged))
        var output = original; merged.apply(to: &output)
        XCTAssertEqual(output.metadata?.series, "New series")
        XCTAssertEqual(output.metadata?.writer, "New writer")
    }

    func testExplicitClearAndBookmarkRemovalSurviveStaleDevice() {
        var original = book(); original.bookmarks = [2, 3]
        let old = BookSyncState(contentID: contentHash, book: original, device: "A")
        var edited = old
        var cleared = original; cleared.metadata?.writer = nil; cleared.bookmarks = [3]
        edited.capture(cleared, device: "A", now: Date(timeIntervalSince1970: 100))
        var output = original
        edited.merged(with: old).apply(to: &output)
        XCTAssertNil(output.metadata?.writer)
        XCTAssertEqual(output.bookmarks, [3])
        XCTAssertEqual(edited.fields["bookmark.2"]?.value, "0")
    }

    func testProgressResetWinsAndLayoutStaysLocal() {
        var original = book(); original.recordPosition(12, at: Date(timeIntervalSince1970: 100))
        let old = BookSyncState(contentID: contentHash, book: original, device: "A")
        var reset = old; var updated = original; updated.resetProgress()
        reset.capture(updated, device: "B", now: Date(timeIntervalSince1970: 101))
        var local = original; local.layout = .vertical; local.fitMode = .fitWidth
        old.merged(with: reset).apply(to: &local)
        XCTAssertEqual(local.progress, ReadingProgress())
        XCTAssertEqual(local.layout, .vertical); XCTAssertEqual(local.fitMode, .fitWidth)
    }

    func testClockRollbackAndUnknownFields() {
        let original = book()
        var value = BookSyncState(contentID: contentHash, book: original, device: "A")
        var future = original; future.displayName = "Future"
        value.capture(future, device: "A", now: Date(timeIntervalSince1970: 200))
        let first = value.fields["name"]!.stamp
        future.displayName = "After rollback"
        value.capture(future, device: "B", now: Date(timeIntervalSince1970: 10))
        XCTAssertGreaterThan(value.fields["name"]!.stamp, first)
        value.fields["future.unknown"] = SyncRegister(value: "preserve", stamp: first)
        let merged = value.merged(with: BookSyncState(contentID: contentHash, book: original, device: "C"))
        XCTAssertEqual(merged.fields["future.unknown"]?.value, "preserve")
    }

    func testAssociativityForConflictingEditsAndBookmarkSets() {
        let original = book()
        let seed = BookSyncState(contentID: contentHash, book: original, device: "seed")
        for n in 0..<50 {
            var a = seed, b = seed, c = seed
            var ba = original; ba.displayName = "A\(n)"; ba.bookmarks = [1, 2]
            var bb = original; bb.displayName = "B\(n)"; bb.bookmarks = [2, 3]
            var bc = original; bc.isFavorite = true; bc.bookmarks = [4]
            a.capture(ba, device: "a", now: Date(timeIntervalSince1970: Double(n)))
            b.capture(bb, device: "b", now: Date(timeIntervalSince1970: Double(n + 1)))
            c.capture(bc, device: "c", now: Date(timeIntervalSince1970: Double(n + 2)))
            XCTAssertEqual(a.merged(with: b).merged(with: c), a.merged(with: b.merged(with: c)))
        }
    }

    func testEnvelopeRejectsUnsafeIdentityAndKeepsDeviceIDSeparate() throws {
        let original = book()
        var envelope = CloudBookEnvelope(book: original, state: BookSyncState(contentID: contentHash, book: original, device: "A"))
        XCTAssertTrue(envelope.isValid)
        let remote = envelope.localRecord(account: "account")
        XCTAssertNotEqual(remote.id, original.id)
        XCTAssertEqual(remote.syncAccountID, "account")
        XCTAssertEqual(remote.syncState?.contentID, contentHash)
        envelope.state.contentID = "../not-a-hash"
        XCTAssertFalse(envelope.isValid)
    }

    func testLibraryRoundTripPreservesSyncStateAndOldRecordsRemainCompatible() throws {
        var original = book()
        original.syncState = BookSyncState(contentID: contentHash, book: original, device: "A")
        original.syncAccountID = "account"
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(BookRecord.self, from: data), original)
        let legacy = book()
        XCTAssertNil(try JSONDecoder().decode(BookRecord.self, from: JSONEncoder().encode(legacy)).syncState)
    }
    func testIndependentFirstSyncDoesNotEraseNonemptyMetadata() {
        let complete = book()
        var blank = complete; blank.metadata?.writer = nil
        let a = BookSyncState(contentID: contentHash, book: complete, device: "A")
        let z = BookSyncState(contentID: contentHash, book: blank, device: "Z")
        var output = blank
        a.merged(with: z).apply(to: &output)
        XCTAssertEqual(output.metadata?.writer, "Writer")
        XCTAssertEqual(a.merged(with: z), z.merged(with: a))
    }

    func testIncomingEventPreservesUnflushedPageTurn() {
        var local = book()
        let before = BookSyncState(contentID: contentHash, book: local, device: "A")
        local.syncState = before
        // Same ordering as a page turn followed by an event before the 0.4 s write.
        local.recordPosition(7, at: Date(timeIntervalSince1970: 200))
        var remoteBook = book(); remoteBook.isFavorite = true
        var remote = before
        remote.capture(remoteBook, device: "B", now: Date(timeIntervalSince1970: 100))
        before.mergedPreservingPendingChanges(with: remote, localBook: local, device: "A", now: Date(timeIntervalSince1970: 201)).apply(to: &local)
        XCTAssertEqual(local.progress.currentPage, 7)
        XCTAssertTrue(local.isFavorite)
    }

    func testEnvelopeRejectsClockOverflow() {
        let original = book()
        var envelope = CloudBookEnvelope(book: original, state: BookSyncState(contentID: contentHash, book: original, device: "A"))
        envelope.state.fields["name"]?.stamp.counter = UInt64.max
        XCTAssertFalse(envelope.isValid)
        envelope.state.fields["name"]?.stamp.counter = 0
        envelope.state.fields["name"]?.stamp.milliseconds = Int64.max
        XCTAssertFalse(envelope.isValid)
    }

    func testV1MigrationKeepsByteIdenticalRollbackSnapshot() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let paths = LibraryPaths(root: base.appendingPathComponent("data"), cachesRoot: base.appendingPathComponent("cache"), tempRoot: base.appendingPathComponent("tmp"))
        try paths.createDirectories()
        let data = try LibraryDatabase.encoder().encode(LibraryDatabase.Snapshot(version: 1, books: [book()]))
        try data.write(to: paths.libraryFile)
        let db = LibraryDatabase(paths: paths)
        guard case .loaded(let records) = db.load() else { return XCTFail("v1 did not load") }
        try db.save(records)
        XCTAssertEqual(try Data(contentsOf: paths.root.appendingPathComponent("library.before-v2.json")), data)
        let snapshot = try LibraryDatabase.decoder().decode(LibraryDatabase.Snapshot.self, from: Data(contentsOf: paths.libraryFile))
        XCTAssertEqual(snapshot.version, 2)
        XCTAssertEqual(snapshot.books, records)
    }

    func testLibraryReloadDoesNotInventProgressEditFromFractionalDate() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let paths = LibraryPaths(root: base.appendingPathComponent("data"), cachesRoot: base.appendingPathComponent("cache"), tempRoot: base.appendingPathComponent("tmp"))
        try paths.createDirectories()
        var original = book()
        original.recordPosition(7, at: Date(timeIntervalSince1970: 1_700_000_000.987))
        original.syncState = BookSyncState(contentID: contentHash, book: original, device: "A")
        let before = original.syncState!
        try LibraryDatabase(paths: paths).save([original])
        guard case .loaded(let records) = LibraryDatabase(paths: paths).load(), let restored = records.first else {
            return XCTFail("saved library did not load")
        }
        var after = restored.syncState!
        after.capture(restored, device: "B", now: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(after, before, "Date serialization must not create a newer local progress register")
    }

    func testCounterRolloverProducesValidForwardStamp() {
        var record = book()
        var state = BookSyncState(contentID: contentHash, book: record, device: "A")
        state.fields["name"]?.stamp = SyncStamp(milliseconds: 200_000, counter: UInt64.max - 1, device: "A")
        record.displayName = "Changed"
        state.capture(record, device: "B", now: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(state.fields["name"]?.stamp.milliseconds, 200_001)
        XCTAssertEqual(state.fields["name"]?.stamp.counter, 0)
        XCTAssertTrue(CloudBookEnvelope(book: record, state: state).isValid)
    }

}
