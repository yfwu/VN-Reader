import XCTest
@testable import ComicCore

final class PageFileNameTests: XCTestCase {
    private func name(_ book: String, page: Int = 6, count: Int = 120) -> String {
        PageFileName.make(book: book, page: page, pageCount: count, fileExtension: "jpg")
    }

    func testCountsFromOneAndPadsToTheBookLength() {
        XCTAssertEqual(name("Book", page: 0, count: 9), "Book p1.jpg")
        XCTAssertEqual(name("Book", page: 6, count: 120), "Book p007.jpg")
        XCTAssertEqual(name("Book", page: 119, count: 120), "Book p120.jpg")
    }

    func testKeepsCJKAndPunctuationThatFilesAllow() {
        XCTAssertEqual(name("星之旅人 第 1 卷"), "星之旅人 第 1 卷 p007.jpg")
        XCTAssertEqual(name("Batman (2016) #45"), "Batman (2016) #45 p007.jpg")
    }

    func testRemovesWhatAPathCannotHold() {
        XCTAssertEqual(name("Fate/stay night: 1\\2"), "Fate stay night 1 2 p007.jpg")
        XCTAssertEqual(name("two\nlines\t here"), "two lines here p007.jpg")
        XCTAssertEqual(name("...hidden"), "hidden p007.jpg")
    }

    func testFallsBackToThePageNumberWhenNothingIsLeft() {
        XCTAssertEqual(name(""), "p007.jpg")
        XCTAssertEqual(name(" / : "), "p007.jpg")
    }

    func testLongNamesFitTheFileSystemWithoutSplittingACharacter() {
        let result = name(String(repeating: "漫", count: 200))
        XCTAssertLessThanOrEqual(result.utf8.count, 255)
        XCTAssertTrue(result.hasSuffix("漫 p007.jpg"))
    }
}
