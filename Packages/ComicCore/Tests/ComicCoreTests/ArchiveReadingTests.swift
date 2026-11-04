import XCTest
@testable import ComicCore

/// Real ZIP / RAR4 / RAR5 (solid and non-solid) decoding.
final class ArchiveReadingTests: XCTestCase {
    let simpleArchives: [(String, ArchiveFormat, Bool)] = [
        ("cbz_basic.cbz", .zip, false),
        ("rar4_nonsolid.cbr", .rar4, false),
        ("rar4_solid.cbr", .rar4, true),
        ("rar4_stored.cbr", .rar4, false),
        ("rar5_nonsolid.cbr", .rar5, false),
        ("rar5_solid.cbr", .rar5, true),
        ("rar5_stored.cbr", .rar5, false),
    ]

    func testDetectsFormatByContent() throws {
        for (name, format, _) in simpleArchives {
            XCTAssertEqual(try FormatDetector.detect(fileAt: Fixtures.url(name)), .archive(format), name)
        }
        // A ZIP renamed to .cbr is still a ZIP.
        XCTAssertEqual(try FormatDetector.detect(fileAt: Fixtures.url("zip_named_as.cbr")), .archive(.zip))
        XCTAssertEqual(try FormatDetector.detect(fileAt: Fixtures.url("not_an_archive.cbz")), .otherDocument("PDF"))
        XCTAssertEqual(try FormatDetector.detect(fileAt: Fixtures.url("sevenzip.cb7.cbz")), .unsupportedArchive("7z"))
    }

    func testAllFormatsListAndDecodeEveryPage() throws {
        for (name, format, solid) in simpleArchives {
            let archive = try ArchiveOpener.open(url: Fixtures.url(name))
            XCTAssertEqual(archive.format, format, name)
            XCTAssertEqual(archive.isSolid, solid, name)
            XCTAssertEqual(archive.supportsRandomAccess, !solid, name)
            let manifest = try PageManifest.build(from: archive)
            XCTAssertEqual(manifest.pages.map(\.path), (1...12).map { "\($0).jpg" }, name)
            XCTAssertEqual(manifest.ignoredEntryCount, 6, name)
            XCTAssertNotNil(manifest.comicInfoIndex, name)
            // Random order reads (exercises cursor rewind for RAR).
            for page in [11, 0, 5, 6, 3, 11, 1].map({ manifest.pages[$0] }) {
                let data = try archive.readEntry(at: page.archiveIndex)
                XCTAssertTrue(data.isJPEG, "\(name) \(page.path)")
                XCTAssertEqual(UInt64(data.count), page.size, "\(name) \(page.path)")
            }
        }
    }

    func testSameBytesAcrossFormats() throws {
        let reference = try ArchiveOpener.open(url: Fixtures.url("cbz_basic.cbz"))
        let refManifest = try PageManifest.build(from: reference)
        let refData = try refManifest.pages.map { try reference.readEntry(at: $0.archiveIndex) }
        for (name, _, _) in simpleArchives.dropFirst() {
            let a = try ArchiveOpener.open(url: Fixtures.url(name))
            let m = try PageManifest.build(from: a)
            for (i, p) in m.pages.enumerated() {
                XCTAssertEqual(try a.readEntry(at: p.archiveIndex), refData[i], "\(name) page \(i)")
            }
        }
    }

    func testSequentialExtractionOfSolidArchive() throws {
        for name in ["rar4_solid.cbr", "rar5_solid.cbr", "rar5_solid_webp_png.cbr"] {
            let a = try ArchiveOpener.open(url: Fixtures.url(name))
            let m = try PageManifest.build(from: a)
            var got: [Int: Data] = [:]
            try a.extractSequentially(indices: Set(m.pages.map(\.archiveIndex))) { idx, data in
                got[idx] = data
                return true
            }
            XCTAssertEqual(got.count, m.pageCount, name)
            for p in m.pages { XCTAssertEqual(UInt64(got[p.archiveIndex]!.count), p.size, name) }
        }
    }

    func testSequentialExtractionStopsWhenHandlerReturnsFalse() throws {
        let a = try ArchiveOpener.open(url: Fixtures.url("rar5_solid.cbr"))
        let m = try PageManifest.build(from: a)
        var count = 0
        try a.extractSequentially(indices: Set(m.pages.map(\.archiveIndex))) { _, _ in
            count += 1
            return count < 3
        }
        XCTAssertEqual(count, 3)
    }

    func testNestedCJKNames() throws {
        let expected = ["cover.jpg",
                        "特殊 字元 #&()[]'!/01.jpg",
                        "第1話/ページ 1.jpg", "第1話/ページ 2.jpg", "第1話/ページ 10.jpg",
                        "第2話/ページ 1.jpg", "第2話/ページ 2.jpg", "第2話/ページ 10.jpg",
                        "第10話/ページ 1.jpg", "第10話/ページ 2.jpg", "第10話/ページ 10.jpg"]
        for name in ["cbz_nested_cjk.cbz", "rar4_nested_cjk.cbr", "rar5_nested_cjk.cbr"] {
            let a = try ArchiveOpener.open(url: Fixtures.url(name))
            let m = try PageManifest.build(from: a)
            XCTAssertEqual(m.pages.map(\.path), expected, name)
            XCTAssertTrue(try a.readEntry(at: m.pages[4].archiveIndex).isJPEG, name)
        }
    }

    func testLegacyShiftJISNames() throws {
        // swift-corelibs-foundation (Linux) has no Shift_JIS converter; Apple platforms do.
        try XCTSkipIf(String(data: Data([0x83, 0x79]), encoding: .shiftJIS) == nil, "Shift_JIS unavailable on this platform")
        let a = try ArchiveOpener.open(url: Fixtures.url("cbz_cp932_names.cbz"))
        XCTAssertEqual(a.entries.map(\.path), ["第01話/ページ01.jpg", "第01話/ページ02.jpg"])
    }

    func testWebPAndMixedFormats() throws {
        let a = try ArchiveOpener.open(url: Fixtures.url("cbz_webp.cbz"))
        let m = try PageManifest.build(from: a)
        XCTAssertEqual(m.pageCount, 5)
        XCTAssertTrue(m.pages.allSatisfy { $0.type == .webp })
        XCTAssertTrue(try a.readEntry(at: m.pages[0].archiveIndex).isWebP)

        let mixed = try PageManifest.build(from: ArchiveOpener.open(url: Fixtures.url("cbz_mixed_formats.cbz")))
        XCTAssertEqual(mixed.pages.map(\.type), [.jpeg, .png, .webp, .gif])

        let rar = try ArchiveOpener.open(url: Fixtures.url("rar5_solid_webp_png.cbr"))
        let rm = try PageManifest.build(from: rar)
        XCTAssertEqual(rm.pageCount, 15)
        XCTAssertEqual(rm.pages.first?.path, "001.png")
    }

    func testZip64AndStored() throws {
        for name in ["cbz_zip64.cbz", "cbz_stored_padded.cbz"] {
            let a = try ArchiveOpener.open(url: Fixtures.url(name))
            let m = try PageManifest.build(from: a)
            XCTAssertEqual(m.pages.first?.path, "001.png", name)
            XCTAssertTrue(try a.readEntry(at: m.pages[0].archiveIndex).isPNG, name)
        }
    }

    // MARK: - Failure modes: each must be reported precisely.

    func testEncryptedArchives() throws {
        assertThrows(.encryptedArchive) { _ = try ArchiveOpener.open(url: Fixtures.url("rar5_encrypted_headers.cbr")) }
        for name in ["rar5_encrypted.cbr", "rar4_encrypted.cbr", "cbz_encrypted.cbz"] {
            assertThrows(.encryptedArchive, { _ = try PageManifest.build(from: ArchiveOpener.open(url: Fixtures.url(name))) })
        }
    }

    func testMultiVolume() throws {
        for name in ["rar5_multivolume.part1.cbr", "rar4_multivolume.part1.cbr"] {
            assertThrows(.multiVolumeArchive) { _ = try ArchiveOpener.open(url: Fixtures.url(name)) }
        }
    }

    func testTruncated() throws {
        assertThrows(.truncatedArchive) { _ = try ArchiveOpener.open(url: Fixtures.url("cbz_truncated.cbz")) }
        // RAR: listing may stop early; reading the missing data must fail precisely.
        do {
            let a = try ArchiveOpener.open(url: Fixtures.url("rar5_truncated.cbr"))
            let m = try PageManifest.build(from: a)
            var failures = 0
            for p in m.pages {
                do { _ = try a.readEntry(at: p.archiveIndex) } catch { failures += 1 }
            }
            XCTAssertLessThan(m.pageCount, 12, "truncated listing should not report all pages")
        } catch let e as ComicError {
            XCTAssertTrue([.truncatedArchive, .corruptArchive(detail: "RAR header data")].contains(e) ||
                          { if case .corruptArchive = e { return true }; return false }(), "\(e)")
        }
    }

    func testCorruptRarData() throws {
        let a = try ArchiveOpener.open(url: Fixtures.url("rar5_corrupt_data.cbr"))
        let m = try PageManifest.build(from: a)
        var failed = false
        do {
            try a.extractSequentially(indices: Set(m.pages.map(\.archiveIndex))) { _, _ in true }
        } catch let e as ComicError {
            failed = true
            if case .checksumMismatch = e {} else if case .corruptArchive = e {} else { XCTFail("\(e)") }
        }
        XCTAssertTrue(failed)
    }

    func testNotArchivesAndEmpty() throws {
        assertThrows(.notAnArchive(detected: "PDF")) { _ = try ArchiveOpener.open(url: Fixtures.url("not_an_archive.cbz")) }
        assertThrows(.unsupportedArchiveType("7z")) { _ = try ArchiveOpener.open(url: Fixtures.url("sevenzip.cb7.cbz")) }
        assertThrows(.noImages) { _ = try PageManifest.build(from: ArchiveOpener.open(url: Fixtures.url("cbz_no_images.cbz"))) }
    }

    func testUnsupportedZipMethod() throws {
        assertThrows(.unsupportedCompression(method: "BZIP2")) {
            _ = try PageManifest.build(from: ArchiveOpener.open(url: Fixtures.url("cbz_bzip2.cbz")))
        }
    }

    func testBrokenImageIsStillListed() throws {
        let a = try ArchiveOpener.open(url: Fixtures.url("cbz_broken_image.cbz"))
        let m = try PageManifest.build(from: a)
        XCTAssertEqual(m.pageCount, 3) // decoding failure is handled per page by the reader
    }

    func testEntrySizeLimit() throws {
        let a = try ArchiveOpener.open(url: Fixtures.url("rar5_nonsolid.cbr"), limits: ArchiveLimits(maxEntries: 100, maxEntrySize: 1000))
        let m = try PageManifest.build(from: a)
        XCTAssertThrowsError(try a.readEntry(at: m.pages[0].archiveIndex))
        assertThrows(.tooManyEntries(count: 18, limit: 5)) {
            _ = try ArchiveOpener.open(url: Fixtures.url("cbz_basic.cbz"), limits: ArchiveLimits(maxEntries: 5))
        }
    }
}
