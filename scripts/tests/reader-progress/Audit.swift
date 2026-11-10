import Foundation
import CloudKit
import ComicCore
struct CheckFailure: Error { let description: String }
func check(_ result: @autoclosure () -> Bool, _ label: String) throws {
    guard result() else { throw CheckFailure(description: label) }
    print("PASS: \(label)")
}
@main struct Audit {
    @MainActor static func main() async throws {
        let base = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let fixture = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true).appendingPathComponent("cbz_basic.cbz")
        let account = "isolated-progress-audit"
        let old = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970) - 3600)
        func setup(_ name: String, unread: Bool = false, synced: Bool = true) throws -> (LibraryStore, BookRecord, ReaderViewModel) {
            let dir = base.appendingPathComponent(name)
            let paths = LibraryPaths(root: dir.appendingPathComponent("support"), cachesRoot: dir.appendingPathComponent("cache"), tempRoot: dir.appendingPathComponent("tmp"))
            let library = LibraryStore(paths: paths)
            guard case .imported(var book) = try BookImporter(paths: paths).importBook(from: fixture, existing: []) else { throw CheckFailure(description: "fixture import") }
            guard book.pageCount >= 4 else { throw CheckFailure(description: "fixture must have at least four pages") }
            if !unread { book.recordPosition(0, at: old) }
            if synced {
                let hash = try CloudFileStore.hashFile(paths.archiveFile(book.id, format: book.format))
                book.syncState = BookSyncState(contentID: hash, book: book, device: "original")
                book.syncAccountID = account
            }
            try library.add(book)
            if synced { library.cloudSync.auditBind(account) }
            let initial = library.book(book.id)!
            return (library, initial, ReaderViewModel(record: initial, library: library))
        }
        func remoteRecord(_ book: BookRecord, _ library: LibraryStore, time: Date, page: Int = 2, reset: Bool = false) throws -> CKRecord {
            var remote = book
            if reset { remote.resetProgress() } else { remote.recordPosition(page, at: time) }
            remote.syncState!.capture(remote, device: "remote", now: time)
            let id = CKRecord.ID(recordName: "book-" + remote.syncState!.contentID, zoneID: CKRecordZone.ID(zoneName: CloudSyncEnvironment.zoneName("Library"), ownerName: CKCurrentUserDefaultName))
            let record = CKRecord(recordType: "Book", recordID: id)
            record["payload"] = try JSONEncoder().encode(CloudBookEnvelope(book: remote, state: remote.syncState!)) as CKRecordValue
            record["manifest"] = CKAsset(fileURL: library.paths.manifestFile(remote.id))
            return record
        }
        func attach(_ model: ReaderViewModel, _ library: LibraryStore, _ book: BookRecord) throws {
            model.auditAttach(try BookPageSource(bookID: book.id, paths: library.paths, format: book.format))
        }
        func reload(_ library: LibraryStore, id: UUID) throws -> BookRecord {
            guard case .loaded(let books) = LibraryDatabase(paths: library.paths).load(), let book = books.first(where: { $0.id == id }) else { throw CheckFailure(description: "database reload") }
            return book
        }
        do {
            let (library, book, model) = try setup("fetch-before-attach")
            try await library.cloudSync.auditReceive(remoteRecord(book, library, time: old.addingTimeInterval(1800)))
            let accepted = library.book(book.id)!
            try check(model.currentPage == 2, "remote progress reaches a reader waiting for archive attachment")
            try attach(model, library, book)
            model.pageDidChange(0, visiblePages: [0], userInitiated: false)
            library.saveNow()
            try check(model.currentPage == 2 && library.book(book.id)!.progress.currentPage == 2, "stale attachment and initial callback cannot restore an older page")
            try check(library.book(book.id)!.syncState == accepted.syncState, "passive attachment creates no new sync stamp")
            model.close()
        }
        do {
            let (library, book, model) = try setup("attach-before-fetch")
            let pager = PagerSpy(); model.pager = pager
            try attach(model, library, book)
            model.pageDidChange(0, visiblePages: [0], userInitiated: false)
            try check(library.book(book.id)!.progress == book.progress, "passive opening leaves canonical progress unchanged before first fetch")
            try await library.cloudSync.auditReceive(remoteRecord(book, library, time: old.addingTimeInterval(1800)))
            try check(model.currentPage == 2 && library.book(book.id)!.progress.currentPage == 2, "initial fetch wins over passive opening in the opposite event order")
            try check(pager.restorations.last?.0 == 2 && pager.restorations.last?.1 == false, "fetched progress requests passive pager restoration")
            let accepted = library.book(book.id)!
            model.pageDidChange(2, visiblePages: [1, 2], userInitiated: false)
            model.pageDidChange(0, visiblePages: [0], userInitiated: false)
            model.appSettingsChanged()
            library.saveNow()
            try check(model.currentPage == 2 && library.book(book.id)!.syncState == accepted.syncState, "same-page and stale reflow callbacks do not change logical focus or sync stamps")
            model.jump(to: 1)
            try check(pager.restorations.last?.0 == 1 && pager.restorations.last?.1 == true, "explicit model jump carries user intent to the pager")
            model.pageDidChange(1, visiblePages: [1], userInitiated: true)
            library.saveNow()
            try check(library.book(book.id)!.progress.currentPage == 1 && library.book(book.id)!.syncState!.fields["progress"]!.stamp > accepted.syncState!.fields["progress"]!.stamp,
                      "real navigation after a remote update produces a newer explicit position")
            let durable = try reload(library, id: book.id)
            try check(durable.progress.currentPage == 1, "explicit navigation survives a real database save and reload")
            model.close()
        }
        do {
            let (library, book, model) = try setup("active-reader")
            try attach(model, library, book)
            model.pageDidChange(1, visiblePages: [1], userInitiated: true)
            library.saveNow()
            try await library.cloudSync.auditReceive(remoteRecord(library.book(book.id)!, library, time: Date().addingTimeInterval(60)))
            try check(library.book(book.id)!.progress.currentPage == 2 && model.currentPage == 1, "remote update does not unexpectedly jump an actively navigating reader")
            let accepted = library.book(book.id)!
            model.scenePhaseChanged(.inactive)
            let automaticRequests = library.cloudSync.auditSynchronizationRequests
            model.scenePhaseChanged(.active)
            try check(model.currentPage == 1 && library.cloudSync.auditSynchronizationRequests == automaticRequests + 1,
                      "transient inactive/active requests fresh metadata without jumping to received remote progress")
            model.pageDidChange(1, visiblePages: [1], userInitiated: false)
            model.close()
            try check(library.book(book.id)!.syncState == accepted.syncState && library.book(book.id)!.progress.currentPage == 2,
                      "passive reflow then close preserves the remote position and stamp")
        }
        do {
            let (library, book, model) = try setup("background-resume")
            let pager = PagerSpy(); model.pager = pager
            try attach(model, library, book)
            model.pageDidChange(1, visiblePages: [1], userInitiated: true)
            model.scenePhaseChanged(.background)
            try await library.cloudSync.auditReceive(remoteRecord(library.book(book.id)!, library, time: Date().addingTimeInterval(60)))
            try check(model.currentPage == 1, "background fetch does not move the inactive reader")
            let count = library.cloudSync.auditSynchronizationRequests
            model.scenePhaseChanged(.active)
            try check(model.currentPage == 2 && pager.restorations.last?.1 == false, "foreground restores latest merged progress without user intent")
            try check(library.cloudSync.auditSynchronizationRequests == count + 1, "foreground requests a nonblocking metadata synchronization")
            try await library.cloudSync.auditReceive(remoteRecord(library.book(book.id)!, library, time: Date().addingTimeInterval(120), page: 3))
            try check(model.currentPage == 3, "late foreground fetch is adopted before the next deliberate navigation")
            model.pageDidChange(1, visiblePages: [1], userInitiated: true)
            library.saveNow()
            try check(library.book(book.id)!.progress.currentPage == 1, "deliberate navigation after foreground fetch wins even after a future remote clock")
            model.close()
        }
        do {
            let (library, book, model) = try setup("automatic-book-switch")
            let before = library.cloudSync.auditSynchronizationRequests
            model.open()
            try check(library.cloudSync.auditSynchronizationRequests == before + 1,
                      "book open requests automatic synchronization without awaiting it")
            model.open()
            try check(library.cloudSync.auditSynchronizationRequests == before + 1,
                      "duplicate open while loading does not request another checkpoint")
            for _ in 0..<5000 {
                if model.isReady { break }
                await Task.yield()
            }
            try check(model.isReady && model.bookID == book.id,
                      "local archive opens while automatic network request is deferred")
            model.close(); model.close()
            try check(library.cloudSync.auditSynchronizationRequests == before + 2,
                      "book close requests one shared automatic checkpoint after local flush")
        }
        do {
            let (library, book, model) = try setup("local-opening-activity", unread: true)
            let originalState = book.syncState
            try attach(model, library, book)
            model.pageDidChange(0, visiblePages: [0], userInitiated: false)
            try check(library.book(book.id)!.status == .unread && library.book(book.id)!.syncState == originalState,
                      "passive opening does not mutate canonical unread status or sync state")
            try check(library.visibleBooks(search: "", sort: .recentlyRead, filter: .reading).first?.id == book.id && library.continueReading?.id == book.id,
                      "local opening still appears as reading in filters and Continue")
            try check(library.visibleBooks(search: "", sort: .recentlyRead, filter: .unread).isEmpty,
                      "local reading projection consistently leaves the unread filter")
            let restarted = LibraryStore(paths: library.paths)
            try check(restarted.continueReading?.id == book.id && restarted.book(book.id)!.progress.lastReadAt == nil,
                      "local opening recency survives restart separately from canonical progress")
            library.saveInfoChanges(book.id, displayName: nil, changes: [.title: "Edited title"])
            let payload = try library.cloudSync.auditRecord(book.syncState!.contentID)!["payload"] as! Data
            let outgoing = try JSONDecoder().decode(CloudBookEnvelope.self, from: payload)
            try check(outgoing.state.fields["progress"] == originalState!.fields["progress"],
                      "metadata editing and CloudKit record provider never leak local reading projection")
            let projected = library.continueReading!
            library.saveInfo(book.id, displayName: projected.displayName, metadata: projected.metadata ?? ComicMetadata())
            try check(library.book(book.id)!.progress.lastReadAt == nil && library.book(book.id)!.syncState!.fields["progress"] == originalState!.fields["progress"],
                      "full metadata save from a projected UI record does not copy its opening timestamp")
            var second = book; second.id = UUID(); second.displayName = "Other"; second.syncState = nil; second.syncAccountID = nil
            second.importedAt = Date().addingTimeInterval(60)
            try library.add(second)
            try check(library.visibleBooks(search: "", sort: .recentlyRead, filter: .all).first?.id == book.id,
                      "local opening drives recent-reading sort without changing other books")
            library.resetProgress(book.id)
            try check(library.continueReading == nil && library.visibleBooks(search: "", sort: .recentlyRead, filter: .unread).contains(where: { $0.id == book.id }),
                      "explicit local reset clears local opening activity")
            library.recordOpened(book.id)
            // Use a read state before resetting so the reset is a distinct remote edit.
            var remoteRead = library.book(book.id)!; remoteRead.recordPosition(1, at: old)
            remoteRead.syncState!.capture(remoteRead, device: "remote", now: Date().addingTimeInterval(60))
            try await library.cloudSync.auditReceive(remoteRecord(remoteRead, library, time: Date().addingTimeInterval(120), reset: true))
            try check(library.continueReading == nil, "newer remote reset is not hidden by older device-local opening activity")
            model.close()
        }
        do {
            let (library, book, model) = try setup("invalid-local-activity", unread: true)
            let file = library.paths.root.appendingPathComponent("reader-activity.json")
            let catalogue = try Data(contentsOf: library.paths.libraryFile)
            try Data("invalid local activity".utf8).write(to: file)
            let reopened = LibraryStore(paths: library.paths)
            try check(reopened.book(book.id)?.progress == book.progress && reopened.book(book.id)?.syncState == book.syncState && reopened.writeProtection == nil,
                      "corrupt optional reading activity does not block or alter the canonical catalogue")
            try FileManager.default.removeItem(at: file)
            try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
            library.recordOpened(book.id)
            let afterFailure = try Data(contentsOf: library.paths.libraryFile)
            try check(library.book(book.id) == book && afterFailure == catalogue,
                      "failed optional activity write leaves canonical catalogue bytes and sync state unchanged")
            model.close()
        }
        do {
            let (library, book, model) = try setup("offline-reading", unread: true, synced: false)
            try attach(model, library, book)
            try check(library.continueReading?.id == book.id && library.book(book.id)!.syncState == nil,
                      "offline-only opening still appears in Continue without cloud state")
            model.pageDidChange(1, visiblePages: [1], userInitiated: true)
            model.close()
            let durable = try reload(library, id: book.id)
            try check(durable.progress.currentPage == 1 && durable.status == .reading && durable.syncState == nil,
                      "offline reading navigation and persistence retain existing behavior")
        }
        do {
            let (library, book, model) = try setup("final-spread")
            model.pageDidChange(book.pageCount - 2, visiblePages: [book.pageCount - 2, book.pageCount - 1], userInitiated: true)
            library.saveNow()
            let final = library.book(book.id)!
            try check(model.currentPage == book.pageCount - 2 && final.progress.currentPage == book.pageCount - 2 && final.progress.finished,
                      "final spread preserves exact focused page and marks completion separately")
            let transferred = CloudBookEnvelope(book: final, state: final.syncState!).localRecord(account: account)
            try check(transferred.layout == .single && transferred.progress.currentPage == book.pageCount - 2 && transferred.progress.finished,
                      "remote single-page copy resumes at the focused logical page and retains completion")
            model.close()
        }
        print("All actual reader/library/progress merge checks passed; network and real preferences were forbidden.")
    }
}
