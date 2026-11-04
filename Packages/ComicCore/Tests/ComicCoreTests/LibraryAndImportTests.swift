import XCTest
@testable import ComicCore

private struct FakeCover: CoverRendering {
    func coverJPEG(from imageData: Data) -> Data? { imageData.isJPEG || imageData.isPNG || imageData.isWebP ? Data([0xFF, 0xD8, 0xFF]) : nil }
}

private struct FixedDiskSpace: DiskSpaceProviding {
    var bytes: Int64
    func availableCapacity(for url: URL) -> Int64? { bytes }
}

final class LibraryAndImportTests: XCTestCase {
    var paths: LibraryPaths!

    override func setUpWithError() throws {
        let root = try Fixtures.tempDir(self)
        paths = LibraryPaths(root: root.appendingPathComponent("support"), cachesRoot: root.appendingPathComponent("caches"),
                             tempRoot: root.appendingPathComponent("tmp"))
    }

    private func importer() -> BookImporter { BookImporter(paths: paths, coverRenderer: FakeCover()) }

    /// Copies a fixture to a "user" location so we can check it is never touched.
    private func userCopy(_ name: String, as newName: String? = nil) throws -> URL {
        let dir = paths.root.deletingLastPathComponent().appendingPathComponent("user-files/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(newName ?? name)
        try FileManager.default.copyItem(at: Fixtures.url(name), to: dest)
        return dest
    }

    private func imported(_ outcome: ImportOutcome, file: StaticString = #filePath, line: UInt = #line) -> BookRecord? {
        if case .imported(let r) = outcome { return r }
        XCTFail("expected import, got \(outcome)", file: file, line: line)
        return nil
    }

    func testImportEveryFormatAndReadOffline() throws {
        var library: [BookRecord] = []
        for name in ["cbz_basic.cbz", "rar4_nonsolid.cbr", "rar4_solid.cbr", "rar5_nonsolid.cbr", "rar5_solid.cbr",
                     "zip_named_as.cbr", "cbz_webp.cbz"] {
            let src = try userCopy(name)
            guard let r = imported(try importer().importBook(from: src, existing: library)) else { continue }
            library.append(r)
            XCTAssertTrue(FileManager.default.fileExists(atPath: paths.archiveFile(r.id, format: r.format).path), name)
            XCTAssertTrue(r.hasCover, name)
            XCTAssertGreaterThan(r.pageCount, 0)
            // Reading uses only the managed copy: remove the source to prove offline use.
            try FileManager.default.removeItem(at: src)
            let source = try BookPageSource(bookID: r.id, paths: paths, format: r.format)
            source.startPreparation()
            let first = try awaitResult { try await source.pageData(0) }
            let last = try awaitResult { try await source.pageData(r.pageCount - 1) }
            XCTAssertFalse(first.isEmpty)
            XCTAssertFalse(last.isEmpty)
            source.close()
        }
        XCTAssertEqual(library.first { $0.originalFileName == "zip_named_as.cbr" }?.format, .zip)
        XCTAssertEqual(library.first { $0.originalFileName == "cbz_basic.cbz" }?.metadata?.title, "測試標題")
        // ComicInfo Manga=YesAndRightToLeft → RTL default.
        XCTAssertEqual(library.first { $0.originalFileName == "cbz_basic.cbz" }?.readingDirection, .rightToLeft)
        XCTAssertEqual(Set(library.map(\.id)).count, library.count)
    }

    func testDuplicateAndSameNameRules() throws {
        let i = importer()
        let a = imported(try i.importBook(from: userCopy("cbz_basic.cbz", as: "Book.cbz"), existing: []))!
        // Same content again (different location / name) → duplicate, nothing added.
        let again = try i.importBook(from: userCopy("cbz_basic.cbz", as: "Other name.cbz"), existing: [a])
        XCTAssertEqual(again, .duplicate(existing: a.id))
        // Different content, same file name → separate book, distinct display name, no overwrite.
        let b = imported(try i.importBook(from: userCopy("cbz_webp.cbz", as: "Book.cbz"), existing: [a]))!
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertEqual(a.displayName, "Book")
        XCTAssertEqual(b.displayName, "Book (2)")
        let c = imported(try i.importBook(from: userCopy("rar5_solid.cbr", as: "Book.cbr"), existing: [a, b]))!
        XCTAssertEqual(c.displayName, "Book (3)")
        XCTAssertNotEqual(try Data(contentsOf: paths.archiveFile(a.id, format: .zip)),
                          try Data(contentsOf: paths.archiveFile(b.id, format: .zip)))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: paths.booksDir.path).count, 3)
    }

    func testFailuresLeaveNothingBehind() throws {
        let cases: [(String, ComicError)] = [
            ("cbz_no_images.cbz", .noImages),
            ("cbz_truncated.cbz", .truncatedArchive),
            ("not_an_archive.cbz", .notAnArchive(detected: "PDF")),
            ("sevenzip.cb7.cbz", .unsupportedArchiveType("7z")),
            ("rar5_encrypted_headers.cbr", .encryptedArchive),
            ("rar5_encrypted.cbr", .encryptedArchive),
            ("cbz_encrypted.cbz", .encryptedArchive),
            ("rar5_multivolume.part1.cbr", .multiVolumeArchive),
            ("cbz_bzip2.cbz", .unsupportedCompression(method: "BZIP2")),
        ]
        for (name, expected) in cases {
            assertThrows(expected) { _ = try importer().importBook(from: try userCopy(name), existing: []) }
        }
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: paths.booksDir.path))?.count ?? 0, 0)
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: paths.importStagingDir.path))?.count ?? 0, 0)
    }

    func testCancelCleansUp() throws {
        var calls = 0
        assertThrows(.cancelled) {
            _ = try importer().importBook(from: try userCopy("rar5_stored.cbr"), existing: [], isCancelled: {
                calls += 1
                return calls > 1
            })
        }
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: paths.importStagingDir.path))?.count ?? 0, 0)
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: paths.booksDir.path))?.count ?? 0, 0)
    }

    func testInsufficientDiskSpace() throws {
        let i = importer()
        i.diskSpace = FixedDiskSpace(bytes: 50 * 1024 * 1024)
        do {
            _ = try i.importBook(from: userCopy("cbz_basic.cbz"), existing: [])
            XCTFail("expected failure")
        } catch ComicError.insufficientDiskSpace(let required, let available) {
            XCTAssertGreaterThan(required, available)
        }
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: paths.booksDir.path))?.count ?? 0, 0)
    }

    func testUnreadableSource() {
        let missing = paths.root.appendingPathComponent("nope/missing.cbz")
        XCTAssertThrowsError(try importer().importBook(from: missing, existing: [])) { e in
            guard case ComicError.sourceUnreadable = e else { return XCTFail("\(e)") }
        }
    }

    func testDeleteKeepsUserOriginal() throws {
        let src = try userCopy("rar5_solid.cbr")
        let r = imported(try importer().importBook(from: src, existing: []))!
        let s = try BookPageSource(bookID: r.id, paths: paths, format: r.format)
        s.startPreparation()
        _ = try awaitResult { try await s.pageData(r.pageCount - 1) }
        s.close()
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.extractedDir(r.id).path))
        StorageMaintenance.deleteBook(r.id, paths: paths)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.bookDir(r.id).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.extractedDir(r.id).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: src.path))
        XCTAssertEqual(try Data(contentsOf: src), try Data(contentsOf: Fixtures.url("rar5_solid.cbr")))
    }

    func testLaunchCleanupRemovesIncompleteData() throws {
        try paths.createDirectories()
        let fm = FileManager.default
        try fm.createDirectory(at: paths.importStagingDir.appendingPathComponent("job1"), withIntermediateDirectories: true)
        let orphan = UUID()
        try fm.createDirectory(at: paths.bookDir(orphan), withIntermediateDirectories: true)
        try fm.createDirectory(at: paths.extractedDir(orphan), withIntermediateDirectories: true)
        let kept = imported(try importer().importBook(from: userCopy("cbz_basic.cbz"), existing: []))!
        let report = StorageMaintenance.cleanUp(paths: paths, knownBooks: [kept.id])
        XCTAssertEqual(report.removedStagingJobs, 1)
        XCTAssertEqual(report.removedOrphanBooks, 1)
        XCTAssertEqual(report.removedOrphanCaches, 1)
        XCTAssertTrue(fm.fileExists(atPath: paths.bookDir(kept.id).path))
    }

    func testDatabaseRoundTripAndRecovery() throws {
        let db = LibraryDatabase(paths: paths)
        XCTAssertEqual(db.load(), .empty)
        var r = BookRecord(displayName: "名稱", originalFileName: "a.cbz", format: .zip, isSolid: false, fileSize: 10,
                           pageCount: 30, importedAt: Date(timeIntervalSince1970: 1_600_000_000), fingerprint: "f", hasCover: true)
        r.recordPosition(12, at: Date(timeIntervalSince1970: 1_700_000_000))
        r.readingDirection = .rightToLeft
        r.fitMode = .fitWidth
        try db.save([r])
        XCTAssertEqual(LibraryDatabase(paths: paths).load(), .loaded([r]))
        // Corrupt the main file: the backup made at the last successful load is used.
        try Data("{ not json".utf8).write(to: paths.libraryFile)
        XCTAssertEqual(LibraryDatabase(paths: paths).load(), .recoveredFromBackup([r]))
        XCTAssertEqual(LibraryDatabase(paths: paths).load(), .loaded([r]))
    }

    func testOlderRecordsDecodeWithDefaults() throws {
        let json = """
        {"version":1,"books":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","displayName":"x","originalFileName":"x.cbz",
        "format":"zip","fileSize":1,"pageCount":2,"importedAt":"2024-01-01T00:00:00Z","fingerprint":"f"}]}
        """
        try paths.createDirectories()
        try Data(json.utf8).write(to: paths.libraryFile)
        guard case .loaded(let books) = LibraryDatabase(paths: paths).load() else { return XCTFail() }
        XCTAssertEqual(books.first?.readingDirection, .leftToRight)
        XCTAssertEqual(books.first?.bookmarks, [])
        XCTAssertEqual(books.first?.status, .unread)
    }

    func testComicInfo() {
        let xml = Data("""
        <?xml version="1.0"?><ComicInfo><Title>T</Title><Series>S</Series><Number>2</Number>
        <Manga>YesAndRightToLeft</Manga><Pages><Page Image="0"/></Pages></ComicInfo>
        """.utf8)
        let m = ComicInfoParser.parse(xml)
        XCTAssertEqual(m?.title, "T")
        XCTAssertEqual(m?.number, "2")
        XCTAssertEqual(m?.prefersRightToLeft, true)
        XCTAssertNil(ComicInfoParser.parse(Data("garbage".utf8)))
    }
}

/// Runs an async throwing closure synchronously (tests only).
func awaitResult<T>(timeout: TimeInterval = 30, _ body: @escaping () async throws -> T) throws -> T {
    let sem = DispatchSemaphore(value: 0)
    var result: Result<T, Error>!
    Task.detached {
        do { result = .success(try await body()) } catch { result = .failure(error) }
        sem.signal()
    }
    guard sem.wait(timeout: .now() + timeout) == .success else { throw ComicError.ioError(detail: "timeout") }
    return try result.get()
}
