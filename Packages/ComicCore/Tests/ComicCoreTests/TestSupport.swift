import Foundation
import XCTest
@testable import ComicCore

enum Fixtures {
    static func url(_ name: String) -> URL {
        Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil)!
    }

    /// Fresh temporary directory, removed by the test's teardown block.
    static func tempDir(_ test: XCTestCase) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vnreader-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        test.addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }
}

extension Data {
    var isJPEG: Bool { count > 3 && self[startIndex] == 0xFF && self[startIndex + 1] == 0xD8 }
    var isPNG: Bool { starts(with: [0x89, 0x50, 0x4E, 0x47]) }
    var isWebP: Bool { count > 12 && subdata(in: startIndex + 8..<startIndex + 12) == Data("WEBP".utf8) }
}

func assertThrows(_ expected: ComicError, file: StaticString = #filePath, line: UInt = #line, _ body: () throws -> Void) {
    do {
        try body()
        XCTFail("expected \(expected), got success", file: file, line: line)
    } catch let e as ComicError {
        XCTAssertEqual(e, expected, file: file, line: line)
    } catch {
        XCTFail("expected \(expected), got \(error)", file: file, line: line)
    }
}
