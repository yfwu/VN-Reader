import XCTest
import ComicCore

final class SpreadLayoutInvariantTests: XCTestCase {
    /// Discovery order can make any subset of page dimensions known. Every such
    /// layout must retain the entire book and keep already-wide images intact.
    func testKnownWidePagesRemainStandaloneWithoutLosingOrDuplicatingPages() {
        for count in 0...10 {
            for mask in 0..<(1 << count) {
                let wide = Set((0..<count).filter { mask & (1 << $0) != 0 })
                for cover in [false, true] {
                    for shift in [false, true] {
                        let layout = SpreadLayout(pageCount: count, coverAlone: cover, shift: shift, widePages: wide)
                        XCTAssertEqual(layout.spreads.flatMap(\.pages), Array(0..<count))
                        for spread in layout.spreads {
                            XCTAssertTrue((1...2).contains(spread.pages.count))
                            XCTAssertTrue(spread.pages.count == 1 || Set(spread.pages).isDisjoint(with: wide))
                            XCTAssertEqual(spread.screenOrder(.leftToRight), spread.pages)
                            XCTAssertEqual(spread.screenOrder(.rightToLeft), Array(spread.pages.reversed()))
                            for page in spread.pages {
                                XCTAssertEqual(layout.spreads[layout.spreadIndex(containing: page)].pages, spread.pages)
                            }
                        }
                    }
                }
            }
        }
    }
}
