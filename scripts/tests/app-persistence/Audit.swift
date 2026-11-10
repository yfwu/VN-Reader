import Foundation
import ComicCore

struct CheckFailure: Error { let description: String }
func check(_ result: @autoclosure () -> Bool, _ label: String) throws {
    guard result() else { throw CheckFailure(description: label) }
    print("PASS: \(label)")
}
@main struct Audit {
    @MainActor static func main() async throws {
        let fm = FileManager.default
        let base = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let paths = LibraryPaths(root: base.appendingPathComponent("support"), cachesRoot: base.appendingPathComponent("caches"), tempRoot: base.appendingPathComponent("tmp"))
        let inbox = base.appendingPathComponent("Documents/Inbox")
        try fm.createDirectory(at: inbox, withIntermediateDirectories: true)
        let fixtures = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        func source(_ fixture: String, _ name: String) throws -> URL {
            let url = inbox.appendingPathComponent(name)
            try fm.copyItem(at: fixtures.appendingPathComponent(fixture), to: url)
            return url
        }
        let library = LibraryStore(paths: paths)
        let coordinator = ImportCoordinator(library: library)
        func settle() async throws {
            for _ in 0..<500 {
                if coordinator.activeCount == 0 {
                    try await Task.sleep(nanoseconds: 50_000_000)
                    return
                }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            throw CheckFailure(description: "import timed out")
        }
        let successful = try source("cbz_basic.cbz", "successful.cbz")
        coordinator.importFiles([successful], securityScoped: false, deleteAfterImport: true)
        try await settle()
        if library.books.count != 1 {
            throw CheckFailure(description: "Unexpected import result: \(coordinator.jobs.map { String(describing: $0.state) }); notice: \(library.notice ?? "none")")
        }
        try check(library.books.count == 1, "successful import publishes exactly one book")
        try check(!fm.fileExists(atPath: successful.path), "successful durable import removes Inbox copy")
        guard case .loaded(let diskBooks) = LibraryDatabase(paths: paths).load() else { throw CheckFailure(description: "cannot reload saved library") }
        try check(diskBooks.count == 1, "successful import is actually saved")
        let original = library.books[0]
        let unreadable = try source("not_an_archive.cbz", "invalid.cbz")
        coordinator.importFiles([unreadable], securityScoped: false, deleteAfterImport: true)
        try await settle()
        try check(fm.fileExists(atPath: unreadable.path), "failed archive validation retains Inbox copy")
        let cancelled = try source("cbz_webp.cbz", "cancelled.cbz")
        coordinator.importFiles([cancelled], securityScoped: false, deleteAfterImport: true)
        coordinator.cancel(coordinator.jobs.last!)
        try await settle()
        try check(fm.fileExists(atPath: cancelled.path), "cancelled import retains Inbox copy")
        // Deliberately make the persistence destination unreadable after startup.
        try fm.removeItem(at: paths.libraryFile)
        try fm.createDirectory(at: paths.libraryFile, withIntermediateDirectories: true)
        let saveFailure = try source("cbz_webp.cbz", "save-failure.cbz")
        coordinator.importFiles([saveFailure], securityScoped: false, deleteAfterImport: true)
        try await settle()
        try check(library.books.count == 1, "failed persistence never publishes imported record")
        try check(fm.fileExists(atPath: saveFailure.path), "failed persistence retains Inbox copy")
        try check(coordinator.jobs.contains { if case .failed = $0.state { return $0.fileName == "save-failure.cbz" }; return false }, "failed persistence reports failed import")
        library.rename(original.id, to: "Should not be published")
        try check(library.book(original.id)?.displayName == original.displayName, "failed rename does not publish unsaved metadata")
        library.batchEdit([original.id], changes: [.series: "Should not be published"], numberFrom: nil, nameStyle: nil)
        try check(library.book(original.id)?.metadata == original.metadata, "failed batch edit preserves published metadata")
        library.delete(original.id)
        try check(library.books.count == 1, "failed delete keeps library record")
        try check(fm.fileExists(atPath: paths.archiveFile(original.id, format: original.format).path), "failed delete keeps archive")
        print("All app persistence checks passed. Synthetic data: \(base.path)")
    }
}
