import XCTest
@testable import ComicCore

final class NavigationTests: XCTestCase {
    typealias N = ReaderNavigation

    func testTapZones() {
        XCTAssertEqual(N.region(x: 10, width: 1000), .left)
        XCTAssertEqual(N.region(x: 500, width: 1000), .center)
        XCTAssertEqual(N.region(x: 990, width: 1000), .right)
    }

    func testLTRTapsAndSwipes() {
        XCTAssertEqual(N.action(for: .right, direction: .leftToRight), .next)
        XCTAssertEqual(N.action(for: .left, direction: .leftToRight), .previous)
        XCTAssertEqual(N.action(for: .center, direction: .leftToRight), .toggleChrome)
        XCTAssertEqual(N.action(for: .fingerMovedLeft, direction: .leftToRight), .next)
        XCTAssertEqual(N.action(for: .fingerMovedRight, direction: .leftToRight), .previous)
        XCTAssertEqual(N.pageOnRight(of: 3, direction: .leftToRight), 4)
    }

    func testRTLTapsAndSwipes() {
        XCTAssertEqual(N.action(for: .left, direction: .rightToLeft), .next)
        XCTAssertEqual(N.action(for: .right, direction: .rightToLeft), .previous)
        XCTAssertEqual(N.action(for: .fingerMovedRight, direction: .rightToLeft), .next)
        XCTAssertEqual(N.action(for: .fingerMovedLeft, direction: .rightToLeft), .previous)
        XCTAssertEqual(N.pageOnLeft(of: 3, direction: .rightToLeft), 4)
        XCTAssertEqual(N.pageOnRight(of: 3, direction: .rightToLeft), 2)
    }

    func testBoundaries() {
        XCTAssertNil(N.apply(.previous, to: 0, pageCount: 5))
        XCTAssertNil(N.apply(.next, to: 4, pageCount: 5))
        XCTAssertEqual(N.apply(.next, to: 0, pageCount: 5), 1)
        // Rapid repeated "next" never overshoots.
        var p = 0
        for _ in 0..<100 { p = N.apply(.next, to: p, pageCount: 5) ?? p }
        XCTAssertEqual(p, 4)
    }

    func testDirectionChangeKeepsLogicalPage() {
        // RTL books start at logical page 0 (the first page), never the last.
        var record = BookRecord(displayName: "b", originalFileName: "b.cbr", format: .rar5, isSolid: false,
                                fileSize: 1, pageCount: 20, fingerprint: "x", hasCover: false)
        record.readingDirection = .rightToLeft
        XCTAssertEqual(record.progress.currentPage, 0)
        record.recordPosition(7)
        record.readingDirection = .leftToRight
        XCTAssertEqual(record.progress.currentPage, 7)
        record.readingDirection = .rightToLeft
        XCTAssertEqual(record.progress.currentPage, 7)
        XCTAssertEqual(N.action(for: .left, direction: record.readingDirection), .next)
    }

    func testPrefetchOrder() {
        XCTAssertEqual(N.prefetchOrder(around: 5, pageCount: 10), [5, 6, 4, 7])
        XCTAssertEqual(N.prefetchOrder(around: 0, pageCount: 10), [0, 1, 2])
        XCTAssertEqual(N.prefetchOrder(around: 9, pageCount: 10), [9, 8])
        XCTAssertEqual(N.prefetchOrder(around: 0, pageCount: 1), [0])
    }

    func testSpreads() {
        let s = SpreadLayout(pageCount: 6)
        XCTAssertEqual(s.spreads.map(\.pages), [[0], [1, 2], [3, 4], [5]])
        XCTAssertEqual(s.spreads[1].screenOrder(.rightToLeft), [2, 1])
        XCTAssertEqual(s.spreads[1].screenOrder(.leftToRight), [1, 2])
        let shifted = SpreadLayout(pageCount: 6, coverAlone: true, shift: true)
        XCTAssertEqual(shifted.spreads.map(\.pages), [[0], [1], [2, 3], [4, 5]])
        let wide = SpreadLayout(pageCount: 6, coverAlone: false, widePages: [2])
        XCTAssertEqual(wide.spreads.map(\.pages), [[0, 1], [2], [3, 4], [5]])
        XCTAssertEqual(wide.spreadIndex(containing: 4), 2)
    }

    func testProgressAndStatus() {
        var r = BookRecord(displayName: "b", originalFileName: "b.cbz", format: .zip, isSolid: false,
                           fileSize: 1, pageCount: 10, fingerprint: "x", hasCover: false)
        XCTAssertEqual(r.status, .unread)
        r.recordPosition(3)
        XCTAssertEqual(r.status, .reading)
        r.recordPosition(99)
        XCTAssertEqual(r.progress.currentPage, 9)
        XCTAssertEqual(r.status, .finished)
        r.resetProgress()
        XCTAssertEqual(r.status, .unread)
        XCTAssertEqual(r.progress.currentPage, 0)
    }
}
