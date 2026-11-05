import XCTest
@testable import ComicCore

final class MetadataEditingTests: XCTestCase {
    private func record(_ file: String, metadata: ComicMetadata? = nil, imported: TimeInterval = 0) -> BookRecord {
        BookRecord(displayName: (file as NSString).deletingPathExtension, originalFileName: file, format: .zip,
                   isSolid: false, fileSize: 1, pageCount: 10, importedAt: Date(timeIntervalSince1970: imported),
                   fingerprint: file, hasCover: false, metadata: metadata)
    }

    func testDisplayNameStyles() {
        let us = ComicMetadata(title: "Rebirth", series: "Batman", number: "45", volume: "2016")
        XCTAssertEqual(MetadataEditor.displayName(style: .seriesIssue, metadata: us), "Batman (2016) #45")
        XCTAssertEqual(MetadataEditor.displayName(style: .title, metadata: us), "Rebirth")

        var m = us
        m.volume = "2"
        XCTAssertEqual(MetadataEditor.displayName(style: .seriesIssue, metadata: m), "Batman Vol. 2 #45")
        m.volume = "v2"
        XCTAssertEqual(MetadataEditor.displayName(style: .seriesIssue, metadata: m), "Batman v2 #45")
        m.volume = nil
        m.number = nil
        XCTAssertEqual(MetadataEditor.displayName(style: .seriesIssue, metadata: m), "Batman")

        let manga = ComicMetadata(series: "進擊的巨人", number: "3")
        XCTAssertEqual(MetadataEditor.displayName(style: .seriesVolume, metadata: manga, volumeFormat: { "第 \($0) 卷" }),
                       "進擊的巨人 第 3 卷")

        XCTAssertNil(MetadataEditor.displayName(style: .seriesIssue, metadata: ComicMetadata(title: "x")))
        XCTAssertNil(MetadataEditor.displayName(style: .title, metadata: ComicMetadata(series: "S")))
    }

    func testApplyChangesKeepsOtherFieldsAndClears() {
        var r = record("a.cbz", metadata: ComicMetadata(title: "T", series: "Old", writer: "W", prefersRightToLeft: true))
        MetadataEditor.apply([.series: "  New  ", .writer: "", .year: "2016"], to: &r)
        XCTAssertEqual(r.metadata?.series, "New")
        XCTAssertNil(r.metadata?.writer)
        XCTAssertEqual(r.metadata?.year, 2016)
        XCTAssertEqual(r.metadata?.title, "T")
        XCTAssertEqual(r.metadata?.prefersRightToLeft, true)

        MetadataEditor.apply([.year: "abc"], to: &r)
        XCTAssertNil(r.metadata?.year)

        var empty = record("b.cbz")
        MetadataEditor.apply([.series: "S"], to: &empty)
        XCTAssertEqual(empty.metadata?.series, "S")
        MetadataEditor.apply([.series: ""], to: &empty)
        XCTAssertNil(empty.metadata, "metadata with nothing left is removed")
    }

    func testSequentialNumbersFollowNaturalFileOrder() {
        let books = [record("Saga 10.cbz"), record("Saga 2.cbz"), record("Saga 1.cbz")]
        let n = MetadataEditor.sequentialNumbers(for: books, start: 1)
        XCTAssertEqual(n[books[2].id], "1")
        XCTAssertEqual(n[books[1].id], "2")
        XCTAssertEqual(n[books[0].id], "3")
        XCTAssertEqual(MetadataEditor.sequentialNumbers(for: books, start: 7)[books[2].id], "7")
    }

    func testSeriesOrder() {
        let a10 = record("x1.cbz", metadata: ComicMetadata(series: "Batman", number: "10", volume: "2016"))
        let a2 = record("x2.cbz", metadata: ComicMetadata(series: "Batman", number: "2", volume: "2016"))
        let old = record("x3.cbz", metadata: ComicMetadata(series: "Batman", number: "99", volume: "2011"))
        let other = record("Aquaman.cbz")
        let sorted = [a10, other, a2, old].sorted(by: MetadataEditor.seriesOrder)
        XCTAssertEqual(sorted.map(\.id), [other.id, old.id, a2.id, a10.id])
    }

    func testMetadataWithoutNewFieldsStillDecodes() throws {
        let json = #"{"title":"T","series":"S","prefersRightToLeft":false}"#
        let m = try JSONDecoder().decode(ComicMetadata.self, from: Data(json.utf8))
        XCTAssertEqual(m.series, "S")
        XCTAssertNil(m.publisher)
        XCTAssertNil(m.year)
    }

    func testComicInfoReadsCreditsAndYear() {
        let xml = Data("""
        <?xml version="1.0"?><ComicInfo><Series>Saga</Series><Penciller>Fiona Staples</Penciller>
        <Publisher>Image</Publisher><Year>2012</Year></ComicInfo>
        """.utf8)
        let m = ComicInfoParser.parse(xml)
        XCTAssertEqual(m?.penciller, "Fiona Staples")
        XCTAssertEqual(m?.publisher, "Image")
        XCTAssertEqual(m?.year, 2012)
    }
}
