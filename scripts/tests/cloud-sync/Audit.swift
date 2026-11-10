import Foundation
import CloudKit
import ComicCore
struct CheckFailure: Error { let description: String }
func check(_ result: @autoclosure () -> Bool, _ label: String) throws {
    guard result() else { throw CheckFailure(description: label) }; print("PASS: \(label)")
}
@main struct Audit {
    @MainActor static func main() async throws {
        let fm = FileManager.default
        let base = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let paths = LibraryPaths(root: base.appendingPathComponent("support"), cachesRoot: base.appendingPathComponent("caches"), tempRoot: base.appendingPathComponent("tmp"))
        let fixtures = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let library = LibraryStore(paths: paths)
        func add(_ filename: String) throws -> BookRecord {
            guard case .imported(var book) = try BookImporter(paths: paths).importBook(from: fixtures.appendingPathComponent(filename), existing: library.books) else { throw CheckFailure(description: "fixture duplicate") }
            let hash = try CloudFileStore.hashFile(paths.archiveFile(book.id, format: book.format))
            book.syncState = BookSyncState(contentID: hash, book: book, device: "local")
            book.syncAccountID = "audit-account"
            try library.add(book)
            return library.book(book.id)!
        }
        let first = try add("cbz_basic.cbz"), second = try add("cbz_webp.cbz")
        let sync = library.cloudSync; sync.auditBind("audit-account")
        func record(_ book: BookRecord) throws -> CKRecord {
            let id = CKRecord.ID(recordName: "book-" + book.syncState!.contentID, zoneID: CKRecordZone.ID(zoneName: CloudSyncEnvironment.zoneName("Library"), ownerName: CKCurrentUserDefaultName))
            let record = CKRecord(recordType: "Book", recordID: id)
            record["payload"] = try JSONEncoder().encode(CloudBookEnvelope(book: book, state: book.syncState!)) as CKRecordValue
            record["manifest"] = CKAsset(fileURL: paths.manifestFile(book.id))
            return record
        }
        var remote = first
        remote.metadata?.writer = "Remote Writer"
        remote.syncState!.capture(remote, device: "remote", now: Date().addingTimeInterval(-1))
        library.recordPosition(first.id, page: 3)
        library.recordPosition(second.id, page: 1)
        let pending = try sync.auditRecord(first.syncState!.contentID)!
        let before = try JSONDecoder().decode(CloudBookEnvelope.self, from: pending["payload"] as! Data)
        try check(before.state.fields["progress"] == first.syncState!.fields["progress"], "record provider excludes unsaved coalesced progress")
        try await sync.auditReceive(record(remote))
        try check(library.book(first.id)?.progress.currentPage == 3, "remote merge preserves newer coalesced progress")
        try check(library.book(first.id)?.metadata?.writer == "Remote Writer", "remote merge still accepts unrelated remote author edit")
        try check(library.persistedBooks.first(where: { $0.id == first.id })?.progress.currentPage == 3, "merged progress reaches durable snapshot")
        try check(library.persistedBooks.first(where: { $0.id == second.id })?.progress.currentPage == 1, "incoming commit flushes pending edits on other books")
        let secondState = library.persistedBooks.first(where: { $0.id == second.id })!.syncState!
        var secondApplied = second; secondState.apply(to: &secondApplied)
        try check(secondApplied.progress.currentPage == 1, "other book's pending progress also receives a sync stamp")
        library.saveInfoChanges(first.id, displayName: nil, changes: [.title: "Local title"])
        try check(library.book(first.id)?.metadata?.writer == "Remote Writer", "editing only title preserves remote author")
        try check(library.book(first.id)?.metadata?.title == "Local title", "touched title is applied")
        let leaseA = library.acquireReaderLease(first.id), leaseB = library.acquireReaderLease(first.id)
        library.releaseReaderLease(leaseA)
        try check(library.hasActiveReader(first.id), "one closing reader cannot release another reader's protection")
        library.releaseReaderLease(leaseB)
        try check(!library.hasActiveReader(first.id), "last reader releases download protection")
        guard case .loaded(let reloaded) = LibraryDatabase(paths: paths).load(), let loadedFirst = reloaded.first(where: { $0.id == first.id }), var unchangedState = loadedFirst.syncState else { throw CheckFailure(description: "failed to reload persisted sync state") }
        let priorState = unchangedState
        unchangedState.capture(loadedFirst, device: library.syncDeviceID, now: Date().addingTimeInterval(10))
        try check(unchangedState == priorState, "save and reload does not invent a fresh progress edit from Date rounding")
        func ckError(_ code: CKError.Code) -> NSError { NSError(domain: CKErrorDomain, code: code.rawValue) }
        func partial(_ children: [NSError]) -> NSError {
            let values = Dictionary(uniqueKeysWithValues: children.enumerated().map { ("synthetic-\($0.offset)", $0.element) })
            return NSError(domain: CKErrorDomain, code: CKError.partialFailure.rawValue, userInfo: [CKPartialErrorsByItemIDKey: values])
        }
        let conflict = partial([ckError(.serverRecordChanged)])
        var sends = 0
        try await sync.auditSend {
            sends += 1
            if sends == 1 { sync.auditResolvedConflict(); throw conflict }
        }
        try check(sends == 2, "resolved record conflict awaits a successful replacement send")
        sends = 0; var sendFailed = false
        do { try await sync.auditSend { sends += 1; throw conflict } } catch { sendFailed = true }
        try check(sendFailed && sends == 1, "unhandled record conflict is never retried as if merged")
        sends = 0; sendFailed = false
        do {
            try await sync.auditSend { sends += 1; sync.auditResolvedConflict(); throw partial([ckError(.serverRecordChanged), ckError(.networkFailure)]) }
        } catch { sendFailed = true }
        try check(sendFailed && sends == 1, "mixed conflict and network partial failure is not swallowed")
        sends = 0; sendFailed = false
        do { try await sync.auditSend { sends += 1; sync.auditResolvedConflict(); throw conflict } } catch { sendFailed = true }
        try check(sendFailed && sends == 3, "persistent conflicts stop after three total send attempts")
        sends = 0; sendFailed = false
        do {
            try await sync.auditSend {
                sends += 1
                if sends == 1 { sync.auditResolvedConflict(); throw conflict }
                throw ckError(.quotaExceeded)
            }
        } catch { sendFailed = true }
        try check(sendFailed && sends == 2, "quota failure on replacement send remains a failure")
        sends = 0; sendFailed = false
        do { try await sync.auditSend { sends += 1; sync.auditResolvedConflict(); throw partial([]) } } catch { sendFailed = true }
        try check(sendFailed && sends == 1, "empty partial error cannot be mistaken for a resolved conflict")
        sends = 0
        try await sync.auditSend {
            sends += 1
            if sends == 1 { sync.auditResolvedConflict(); throw partial([conflict]) }
        }
        try check(sends == 2, "nested conflict-only partial failures are safely retried")
        let beforeBooks = library.books
        let stateURL = paths.root.appendingPathComponent("cloud-sync-state.json")
        let beforeState = try Data(contentsOf: stateURL)
        try fm.removeItem(at: paths.libraryFile)
        try fm.createDirectory(at: paths.libraryFile, withIntermediateDirectories: true)
        var failed = library.book(first.id)!; failed.isFavorite = true
        failed.syncState!.capture(failed, device: "remote", now: Date().addingTimeInterval(1))
        var threw = false
        do { try await sync.auditReceive(record(failed)) } catch { threw = true }
        try check(threw, "incoming sync fails when library cannot be persisted")
        try check(library.books == beforeBooks, "failed incoming commit leaves published library intact")
        let afterState = try Data(contentsOf: stateURL)
        try check(afterState == beforeState, "failed incoming commit does not advance persisted sync system fields")
        print("All offline coordinator checks passed. No CloudKit backend was allowed. Synthetic data: \(base.path)")
    }
}
