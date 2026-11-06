import XCTest
@testable import ComicCore

/// Importing must not hold the file in memory: iPadOS ends an app that grows
/// past its memory limit, so a multi-gigabyte book would never finish importing.
final class LargeFileImportTests: XCTestCase {
    private func paths(_ root: URL) -> LibraryPaths {
        LibraryPaths(root: root.appendingPathComponent("s"), cachesRoot: root.appendingPathComponent("c"),
                     tempRoot: root.appendingPathComponent("t"))
    }

    /// A file of zeros that takes no disk space: the bytes only exist while they are read.
    private func sparseFile(at url: URL, size: UInt64) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: size)
        try handle.close()
    }

    /// Memory charged to the process, as iOS counts it against the app's limit.
    private func footprint() -> UInt64 {
        #if canImport(Darwin)
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
        #else
        return 0
        #endif
    }

    func testCopyUsesConstantMemory() throws {
        try assertConstantMemory(cloning: false)
    }

    func testCloneUsesConstantMemory() throws {
        try assertConstantMemory(cloning: true)
    }

    private func assertConstantMemory(cloning: Bool) throws {
        #if !canImport(Darwin)
        throw XCTSkip("phys_footprint is Darwin only")
        #else
        let dir = try Fixtures.tempDir(self)
        let source = dir.appendingPathComponent("big.cbz")
        // VN_LARGE_MB=3072 checks a real 3 GB book (keep TMPDIR on a RAM disk: the copy is written out).
        let megabytes = ProcessInfo.processInfo.environment["VN_LARGE_MB"].flatMap(UInt64.init) ?? 128
        let size = megabytes * 1024 * 1024
        try sparseFile(at: source, size: size)

        let importer = BookImporter(paths: paths(dir))
        importer.allowsCloning = cloning
        let start = footprint()
        var peak = start
        // The zeros are not an archive: the copy succeeds, then inspection rejects the file.
        XCTAssertThrowsError(try importer.importBook(from: source, existing: [], progress: { [self] _ in
            peak = max(peak, footprint())
        }))
        peak = max(peak, footprint())

        let grown = peak > start ? peak - start : 0
        print("LARGE import of \(size >> 20) MB: footprint grew \(grown >> 20) MB")
        XCTAssertLessThan(grown, size / 4, "the copy kept the file in memory")
        #endif
    }

    /// A clone is byte-identical, and the book still reads after the original is gone.
    func testClonedBookSurvivesDeletingTheOriginal() throws {
        let dir = try Fixtures.tempDir(self)
        let source = dir.appendingPathComponent("book.cbz")
        try FileManager.default.copyItem(at: Fixtures.url("cbz_basic.cbz"), to: source)
        let p = paths(dir)
        guard case .imported(let record) = try BookImporter(paths: p).importBook(from: source, existing: []) else {
            return XCTFail("not imported")
        }
        let original = try Data(contentsOf: source)
        try FileManager.default.removeItem(at: source)
        XCTAssertEqual(try Data(contentsOf: p.archiveFile(record.id, format: record.format)), original)
        XCTAssertEqual(record.fingerprint, String(format: "%08x-%llu", CRC32.checksum(original), UInt64(original.count)))
    }

    func testOversizedDictionaryIsRefusedBeforeDecompressing() throws {
        let url = Fixtures.url("rar5_solid.cbr")
        assertThrows(.dictionaryTooLarge) {
            _ = try ArchiveOpener.open(url: url, limits: ArchiveLimits(maxDictionarySize: 1024))
        }
        // Stored archives need no dictionary, whatever they declare.
        XCTAssertNoThrow(try ArchiveOpener.open(url: Fixtures.url("rar5_stored.cbr"), limits: ArchiveLimits(maxDictionarySize: 1024)))
    }
}
