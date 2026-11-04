import XCTest
@testable import ComicCore

/// Large-book stress tests. Skipped unless VN_STRESS_DIR points to the output of
/// scripts/fixtures/generate_stress.py. Prints timings (wall clock) and peak memory.
final class StressTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        guard let d = ProcessInfo.processInfo.environment["VN_STRESS_DIR"] else {
            throw XCTSkip("set VN_STRESS_DIR to run stress tests")
        }
        dir = URL(fileURLWithPath: d)
    }

    private func time<T>(_ label: String, _ body: () throws -> T) rethrows -> T {
        let t0 = Date()
        let r = try body()
        print(String(format: "STRESS %@: %.3f s (peak RSS %.0f MB)", label, Date().timeIntervalSince(t0), peakRSSMB()))
        return r
    }

    private func peakRSSMB() -> Double {
        #if os(Linux)
        if let s = try? String(contentsOfFile: "/proc/self/status", encoding: .utf8),
           let line = s.split(separator: "\n").first(where: { $0.hasPrefix("VmHWM:") }),
           let kb = line.split(separator: " ").dropFirst().first.flatMap({ Double($0) }) {
            return kb / 1024
        }
        return 0
        #else
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_maxrss) / 1024 / 1024
        #endif
    }

    private func paths() throws -> LibraryPaths {
        let root = try Fixtures.tempDir(self)
        return LibraryPaths(root: root.appendingPathComponent("s"), cachesRoot: root.appendingPathComponent("c"),
                            tempRoot: root.appendingPathComponent("t"))
    }

    func testImportAndRandomAccess() throws {
        for name in ["stress.cbz", "stress_rar5_nonsolid.cbr"] {
            let url = dir.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let p = try paths()
            let outcome = try time("\(name) import (copy+CRC+list+manifest)") {
                try BookImporter(paths: p).importBook(from: url, existing: [])
            }
            guard case .imported(let r) = outcome else { return XCTFail() }
            XCTAssertEqual(r.pageCount, 1000)
            let s = try time("\(name) open") { try BookPageSource(bookID: r.id, paths: p, format: r.format) }
            var rnd = SystemRandomNumberGenerator()
            let pages = (0..<200).map { _ in Int.random(in: 0..<r.pageCount, using: &rnd) }
            try time("\(name) 200 random page reads") {
                for pg in pages { _ = try s.pageDataSync(pg) }
            }
            try time("\(name) 300 sequential page turns") {
                for pg in 0..<300 { _ = try s.pageDataSync(pg) }
            }
            // Repeated open/close.
            try time("\(name) 20× open/close") {
                for _ in 0..<20 { let x = try BookPageSource(bookID: r.id, paths: p, format: r.format); x.close() }
            }
            StorageMaintenance.deleteBook(r.id, paths: p)
        }
    }

    func testSolidPreparation() throws {
        for name in ["stress_rar5_solid.cbr", "stress_rar4_solid.cbr"] {
            let url = dir.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let p = try paths()
            guard case .imported(let r) = try time("\(name) import", { try BookImporter(paths: p).importBook(from: url, existing: []) }) else {
                return XCTFail()
            }
            let s = try BookPageSource(bookID: r.id, paths: p, format: r.format)
            XCTAssertTrue(s.needsPreparation)
            // Time to first page, then to a far page, then full preparation.
            _ = try time("\(name) first page ready") { try awaitResult(timeout: 600) { try await s.pageData(0) } }
            _ = try time("\(name) page 500 ready") { try awaitResult(timeout: 600) { try await s.pageData(499) } }
            try time("\(name) full preparation") {
                let deadline = Date().addingTimeInterval(900)
                while s.preparation != .complete && Date() < deadline { usleep(50_000) }
            }
            XCTAssertEqual(s.preparation, .complete)
            try time("\(name) 200 random reads from cache") {
                for _ in 0..<200 { _ = try s.pageDataSync(Int.random(in: 0..<r.pageCount)) }
            }
            print("STRESS \(name) cache size: \(StorageMaintenance.directorySize(p.extractedDir(r.id)) / 1_000_000) MB")
            StorageMaintenance.deleteBook(r.id, paths: p)
        }
    }
}
