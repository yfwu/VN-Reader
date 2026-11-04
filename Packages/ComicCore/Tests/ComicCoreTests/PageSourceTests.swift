import XCTest
@testable import ComicCore

final class PageSourceTests: XCTestCase {
    func makeBook(_ fixture: String) throws -> (LibraryPaths, BookRecord) {
        let root = try Fixtures.tempDir(self)
        let paths = LibraryPaths(root: root.appendingPathComponent("s"), cachesRoot: root.appendingPathComponent("c"),
                                 tempRoot: root.appendingPathComponent("t"))
        guard case .imported(let r) = try BookImporter(paths: paths).importBook(from: Fixtures.url(fixture), existing: []) else {
            throw ComicError.cancelled
        }
        return (paths, r)
    }

    func testSolidWaitsForPreparationThenServesFromCache() throws {
        let (paths, r) = try makeBook("rar5_solid.cbr")
        let s = try BookPageSource(bookID: r.id, paths: paths, format: r.format)
        XCTAssertTrue(s.needsPreparation)
        var states: [BookPageSource.Preparation] = []
        let lock = NSLock()
        s.onPreparationChange = { st in lock.lock(); states.append(st); lock.unlock() }
        // Requesting the last page before preparation started starts it implicitly.
        let last = try awaitResult { try await s.pageData(r.pageCount - 1) }
        XCTAssertTrue(last.isJPEG)
        let deadline = Date().addingTimeInterval(10)
        while s.preparation != .complete && Date() < deadline { usleep(10_000) }
        XCTAssertEqual(s.preparation, .complete)
        lock.lock(); XCTAssertTrue(states.contains(.complete)); lock.unlock()
        // A new source for the same book is complete immediately.
        let s2 = try BookPageSource(bookID: r.id, paths: paths, format: r.format)
        XCTAssertEqual(s2.preparation, .complete)
        XCTAssertTrue(try s2.pageDataSync(3).isJPEG)
    }

    func testCancelledWaiterDoesNotHang() throws {
        let (paths, r) = try makeBook("rar4_solid.cbr")
        let s = try BookPageSource(bookID: r.id, paths: paths, format: r.format)
        let t = Task { try await s.pageData(r.pageCount - 1) }
        t.cancel()
        let sem = DispatchSemaphore(value: 0)
        Task { _ = try? await t.value; sem.signal() }
        XCTAssertEqual(sem.wait(timeout: .now() + 10), .success)
        s.close()
    }

    func testRandomAccessSourceConcurrentReads() throws {
        for fixture in ["cbz_basic.cbz", "rar5_nonsolid.cbr", "rar4_nonsolid.cbr"] {
            let (paths, r) = try makeBook(fixture)
            let s = try BookPageSource(bookID: r.id, paths: paths, format: r.format)
            XCTAssertFalse(s.needsPreparation)
            let sizes = try awaitResult { () -> [Int] in
                try await withThrowingTaskGroup(of: (Int, Int).self) { g in
                    for i in (0..<r.pageCount).reversed() { g.addTask { (i, try await s.pageData(i).count) } }
                    var out = [Int](repeating: 0, count: r.pageCount)
                    for try await (i, n) in g { out[i] = n }
                    return out
                }
            }
            XCTAssertEqual(sizes.map(UInt64.init), s.manifest.pages.map(\.size), fixture)
        }
    }

    func testSolidExtractionNeedsDiskSpace() throws {
        struct Tiny: DiskSpaceProviding { func availableCapacity(for url: URL) -> Int64? { 1024 } }
        let (paths, r) = try makeBook("rar5_solid.cbr")
        let s = try BookPageSource(bookID: r.id, paths: paths, format: r.format, diskSpace: Tiny())
        XCTAssertThrowsError(try awaitResult { try await s.pageData(0) }) { e in
            guard case ComicError.insufficientDiskSpace = e else { return XCTFail("\(e)") }
        }
    }
}
