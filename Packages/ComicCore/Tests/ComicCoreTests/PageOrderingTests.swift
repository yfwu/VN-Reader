import XCTest
@testable import ComicCore

final class PageOrderingTests: XCTestCase {
    private func sorted(_ paths: [String]) -> [String] {
        let entries = paths.enumerated().map {
            ArchiveEntry(index: $0.offset, path: $0.element, uncompressedSize: 10, compressedSize: 10,
                         isDirectory: false, isEncrypted: false)
        }
        return try! PageManifest.build(entries: entries, format: .zip, isSolid: false).pages.map(\.path)
    }

    func testUnpaddedNumbers() {
        XCTAssertEqual(sorted(["10.jpg", "2.jpg", "1.jpg", "11.jpg", "3.jpg"]),
                       ["1.jpg", "2.jpg", "3.jpg", "10.jpg", "11.jpg"])
    }

    func testPaddedNumbers() {
        XCTAssertEqual(sorted(["010.jpg", "002.jpg", "001.jpg", "100.jpg"]),
                       ["001.jpg", "002.jpg", "010.jpg", "100.jpg"])
    }

    func testMixedPaddingIsStable() {
        // "01" and "1" are numerically equal: fewer leading zeros first, deterministically.
        XCTAssertEqual(sorted(["01.jpg", "1.jpg", "2.jpg"]), ["1.jpg", "01.jpg", "2.jpg"])
        XCTAssertEqual(sorted(["2.jpg", "1.jpg", "01.jpg"]), ["1.jpg", "01.jpg", "2.jpg"])
    }

    func testPrefixesAndSuffixes() {
        XCTAssertEqual(sorted(["page10.png", "page2.png", "page1.png", "Page3.png"]),
                       ["page1.png", "page2.png", "Page3.png", "page10.png"])
        XCTAssertEqual(sorted(["1-1.jpg", "1.jpg", "1a.jpg", "2.jpg"]), ["1.jpg", "1-1.jpg", "1a.jpg", "2.jpg"])
    }

    func testSubdirectoriesAndRootFilesFirst() {
        XCTAssertEqual(sorted(["ch10/1.jpg", "ch2/1.jpg", "ch2/10.jpg", "ch2/2.jpg", "cover.jpg", "zz.jpg"]),
                       ["cover.jpg", "zz.jpg", "ch2/1.jpg", "ch2/2.jpg", "ch2/10.jpg", "ch10/1.jpg"])
        XCTAssertEqual(sorted(["Vol 1/Chapter 2/001.jpg", "Vol 1/Chapter 10/001.jpg", "Vol 2/001.jpg", "Vol 1/001.jpg"]),
                       ["Vol 1/001.jpg", "Vol 1/Chapter 2/001.jpg", "Vol 1/Chapter 10/001.jpg", "Vol 2/001.jpg"])
    }

    func testCJKAndFullWidthDigits() {
        XCTAssertEqual(sorted(["第10話/1.jpg", "第2話/1.jpg", "第1話/1.jpg"]),
                       ["第1話/1.jpg", "第2話/1.jpg", "第10話/1.jpg"])
        // Full-width digits are normalised (NFKC) to ASCII before comparison.
        XCTAssertEqual(sorted(["ページ１０.jpg", "ページ２.jpg", "ページ1.jpg"]),
                       ["ページ1.jpg", "ページ２.jpg", "ページ１０.jpg"])
    }

    func testSameNameInDifferentFoldersAndDuplicates() {
        XCTAssertEqual(sorted(["b/001.jpg", "a/001.jpg"]), ["a/001.jpg", "b/001.jpg"])
        // Exact duplicate paths keep archive order (stable tie-break by entry index).
        let entries = [ArchiveEntry(index: 0, path: "x/1.jpg", uncompressedSize: 1, compressedSize: 1, isDirectory: false, isEncrypted: false),
                       ArchiveEntry(index: 1, path: "x/1.jpg", uncompressedSize: 2, compressedSize: 2, isDirectory: false, isEncrypted: false)]
        let m = try! PageManifest.build(entries: entries.reversed(), format: .zip, isSolid: false)
        XCTAssertEqual(m.pages.map(\.archiveIndex), [0, 1])
    }

    func testCaseOnlyDifferenceIsDeterministic() {
        let a = sorted(["A.jpg", "a.jpg"])
        let b = sorted(["a.jpg", "A.jpg"])
        XCTAssertEqual(a, b)
        XCTAssertEqual(a, ["A.jpg", "a.jpg"])
    }

    func testIgnoresSystemAndNonPageFiles() {
        XCTAssertEqual(sorted(["1.jpg", "__MACOSX/._1.jpg", "._1.jpg", ".DS_Store", "Thumbs.db", "readme.txt",
                               "ComicInfo.xml", ".hidden/2.jpg", "sub/.DS_Store", "2.PNG", "3.WebP", "4.jpeg"]),
                       ["1.jpg", "2.PNG", "3.WebP", "4.jpeg"])
    }

    func testManifestRoundTripKeepsOrder() throws {
        let a = try ArchiveOpener.open(url: Fixtures.url("cbz_nested_cjk.cbz"))
        let m = try PageManifest.build(from: a)
        let dir = try Fixtures.tempDir(self)
        let url = dir.appendingPathComponent("m.json")
        try PageManifestStore.write(m, to: url)
        XCTAssertEqual(try PageManifestStore.read(url), m)
        // Rebuilding from the same archive gives the identical mapping.
        XCTAssertEqual(try PageManifest.build(from: ArchiveOpener.open(url: Fixtures.url("cbz_nested_cjk.cbz"))), m)
    }

    func testPathTraversalNamesAreOnlyLabels() {
        // Entry names are never used as output paths; "../" names are just sorted like any other.
        XCTAssertEqual(sorted(["../../etc/2.jpg", "1.jpg", "/abs/3.jpg"]).count, 3)
    }
}
