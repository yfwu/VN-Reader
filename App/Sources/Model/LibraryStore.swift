import SwiftUI
import ComicCore

/// The library: book records, persistence and storage housekeeping.
@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var books: [BookRecord] = []
    @Published var notice: String?
    /// Device-local opening recency. Never copied into records sent to CloudKit.
    @Published private var openedAt: [UUID: Date] = [:]

    let paths: LibraryPaths
    private let db: LibraryDatabase
    private(set) var writeProtection: LibraryDatabase.PersistenceError?
    lazy var cloudSync = CloudSyncCoordinator(library: self)
    private var readerLeases: [UUID: UUID] = [:]
    private(set) var persistedBooks: [BookRecord] = []
    private var saveRevision: UInt64 = 0
    private var persistedRevision: UInt64 = 0
    let syncDeviceID: String = {
        let key = CloudSyncEnvironment.defaultsPrefix + "deviceID"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let value = UUID().uuidString
        UserDefaults.standard.set(value, forKey: key)
        return value
    }()
    private var saveWorkItem: DispatchWorkItem?
    private let writeQueue = DispatchQueue(label: "vnreader.library.save", qos: .utility)

    init(paths: LibraryPaths) {
        self.paths = paths
        self.db = LibraryDatabase(paths: paths)
        try? paths.createDirectories()
        switch db.load() {
        case .loaded(let b): books = b
        case .empty: books = []
        case .recoveredFromBackup(let b):
            books = b
            notice = L10n.libraryRecovered
        case .unavailable:
            writeProtection = .unavailable
            notice = L10n.libraryUnavailable
        case .unsupportedVersion(let version):
            writeProtection = .unsupportedVersion(version)
            notice = L10n.libraryUnsupportedVersion
        }
        persistedBooks = books
        if let data = try? Data(contentsOf: readingActivityFile),
           let activity = try? JSONDecoder().decode([UUID: Date].self, from: data) {
            openedAt = activity
        }
        // Only staging and purgeable caches are swept. A missing record never proves
        // the corresponding original book is disposable, even on a later launch.
        let cleanup = StorageMaintenance.cleanUp(paths: paths, knownBooks: Set(books.map(\.id)))
        if notice == nil, cleanup.preservedOrphanBooks > 0 { notice = L10n.libraryOrphansPreserved }
        let paths = self.paths
        DispatchQueue.global(qos: .utility).async {
            // Only touches the purgeable solid-RAR cache.
            StorageMaintenance.trimExtractedCache(paths: paths, limit: 3 << 30, keep: [])
        }
    }

    func book(_ id: UUID) -> BookRecord? { books.first { $0.id == id } }

    // MARK: Queries

    func visibleBooks(search: String, sort: LibrarySort, filter: LibraryFilter) -> [BookRecord] {
        let q = search.trimmingCharacters(in: .whitespaces)
        var list = books.map(presentationRecord).filter { b in
            switch filter {
            case .all: return true
            case .unread: return b.status == .unread
            case .reading: return b.status == .reading
            case .finished: return b.status == .finished
            case .favorites: return b.isFavorite
            }
        }
        if !q.isEmpty {
            list = list.filter { b in
                let m = b.metadata
                return [b.displayName, b.originalFileName, m?.series, m?.title, m?.writer, m?.penciller, m?.publisher]
                    .contains { $0?.localizedStandardContains(q) ?? false }
            }
        }
        switch sort {
        case .recentlyRead:
            list.sort { a, b in
                let da = a.progress.lastReadAt ?? .distantPast, db = b.progress.lastReadAt ?? .distantPast
                return da != db ? da > db : a.importedAt > b.importedAt
            }
        case .imported:
            list.sort { $0.importedAt > $1.importedAt }
        case .title:
            list.sort { NaturalSort.compareNames($0.displayName, $1.displayName) == .orderedAscending }
        case .series:
            list.sort(by: MetadataEditor.seriesOrder)
        }
        return list
    }

    /// Most recently read book that is not finished.
    var continueReading: BookRecord? {
        books.map(presentationRecord).filter { $0.status == .reading }.max { ($0.progress.lastReadAt ?? .distantPast) < ($1.progress.lastReadAt ?? .distantPast) }
    }

    private var readingActivityFile: URL { paths.root.appendingPathComponent("reader-activity.json") }

    private func presentationRecord(_ original: BookRecord) -> BookRecord {
        guard let date = openedAt[original.id] else { return original }
        // A later explicit remote reset still makes a previously opened book unread.
        if original.progress.lastReadAt == nil,
           let stamp = original.syncState?.fields["progress"]?.stamp,
           Double(stamp.milliseconds) / 1000 >= date.timeIntervalSince1970 { return original }
        var book = original
        book.progress.lastReadAt = max(date, book.progress.lastReadAt ?? .distantPast)
        return book
    }

    func recordOpened(_ id: UUID) {
        guard book(id) != nil else { return }
        openedAt[id] = Date()
        saveReadingActivity()
    }

    private func saveReadingActivity() {
        do { try JSONEncoder().encode(openedAt).write(to: readingActivityFile, options: .atomic) }
        catch { notice = ErrorMessages.explain(error).message }
    }

    // MARK: Mutations

    func add(_ record: BookRecord) throws {
        var r = record
        let s = AppSettings.shared
        if r.metadata?.prefersRightToLeft != true { r.readingDirection = s.defaultDirection }
        r.fitMode = s.defaultFitMode
        r.layout = s.defaultLayout
        // Publish and declare success only after the record has reached disk.
        try commit(books + [r])
    }

    func update(_ id: UUID, _ change: (inout BookRecord) -> Void, immediate: Bool = false) {
        guard allowChanges(), let i = books.firstIndex(where: { $0.id == id }) else { return }
        if immediate {
            var next = books
            change(&next[i])
            commitReportingFailure(next)
        } else {
            change(&books[i])
            scheduleSave()
        }
    }

    func rename(_ id: UUID, to name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }
        update(id, { $0.displayName = n }, immediate: true)
    }

    /// Applies only fields touched in the editor to the latest local/remote record.
    func saveInfoChanges(_ id: UUID, displayName: String?, changes: [MetadataField: String]) {
        update(id, { book in
            if let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { book.displayName = name }
            MetadataEditor.apply(changes, to: &book)
        }, immediate: true)
    }

    /// Saves the single-book info editor: display name plus all metadata fields.
    func saveInfo(_ id: UUID, displayName: String, metadata: ComicMetadata) {
        let n = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        update(id, { r in
            if !n.isEmpty { r.displayName = n }
            r.metadata = metadata == ComicMetadata() ? nil : metadata
        }, immediate: true)
    }

    /// Batch edit: sets `changes` on every book, optionally numbers them in file-name
    /// order from `numberFrom`, then optionally rebuilds their display names.
    func batchEdit(_ ids: Set<UUID>, changes: [MetadataField: String], numberFrom: Int?, nameStyle: BookNameStyle?) {
        guard allowChanges() else { return }
        var next = books
        let selected = books.filter { ids.contains($0.id) }
        let numbers = numberFrom.map { MetadataEditor.sequentialNumbers(for: selected, start: $0) } ?? [:]
        for i in next.indices where ids.contains(next[i].id) {
            var c = changes
            if let n = numbers[next[i].id] { c[.number] = n }
            MetadataEditor.apply(c, to: &next[i])
            if let style = nameStyle, let name = Self.generatedName(style, next[i].metadata) {
                next[i].displayName = name
            }
        }
        commitReportingFailure(next)
    }

    static func generatedName(_ style: BookNameStyle, _ metadata: ComicMetadata?) -> String? {
        guard let metadata else { return nil }
        return MetadataEditor.displayName(style: style, metadata: metadata, volumeFormat: L10n.volumeName)
    }

    func resetProgress(_ id: UUID) {
        update(id, { $0.resetProgress() }, immediate: true)
        if book(id)?.progress == ReadingProgress() {
            openedAt.removeValue(forKey: id)
            saveReadingActivity()
        }
    }

    func markFinished(_ id: UUID) {
        update(id, { r in
            r.progress.finished = true
            r.progress.lastReadAt = r.progress.lastReadAt ?? Date()
        }, immediate: true)
    }

    func toggleFavorite(_ id: UUID) { update(id, { $0.isFavorite.toggle() }, immediate: true) }

    func recordPosition(_ id: UUID, page: Int, reachedEnd: Bool = false) {
        update(id, {
            $0.recordPosition(page)
            // Completion and the focused logical page are independent in a spread.
            if reachedEnd { $0.progress.finished = true }
        })
    }

    func delete(_ id: UUID) {
        guard book(id)?.syncState == nil else { notice = L10n.syncDeleteNotice; return }
        guard commitReportingFailure(books.filter { $0.id != id }) else { return }
        openedAt.removeValue(forKey: id)
        saveReadingActivity()
        CoverCache.shared.invalidate(paths.coverFile(id))
        let paths = self.paths
        DispatchQueue.global(qos: .utility).async { StorageMaintenance.deleteBook(id, paths: paths) }
    }

    func removeAllForTesting() {
        let previous = books
        guard commitReportingFailure([]) else { return }
        openedAt.removeAll()
        saveReadingActivity()
        for b in previous { StorageMaintenance.deleteBook(b.id, paths: paths) }
    }

    // MARK: Persistence

    private func allowChanges() -> Bool {
        guard let writeProtection else { return true }
        notice = ErrorMessages.explain(writeProtection).message
        return false
    }

    /// Edits and deletions commit before publishing or removing their files. Import
    /// callers receive failures so they keep the Inbox source and report a failed job.
    private func commit(_ proposed: [BookRecord]) throws {
        let snapshot = capturingSyncChanges(proposed)
        if let writeProtection { throw writeProtection }
        saveWorkItem?.cancel()
        saveWorkItem = nil
        saveRevision += 1
        let revision = saveRevision
        try writeQueue.sync { try db.save(snapshot) }
        books = snapshot
        didPersist(snapshot, revision: revision)
    }

    @discardableResult
    private func commitReportingFailure(_ snapshot: [BookRecord]) -> Bool {
        do { try commit(snapshot); return true }
        catch { notice = ErrorMessages.explain(error).message; return false }
    }

    /// Coalesces frequent updates (page turns) into one background write shortly after.
    private func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.write(sync: false) }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
    }

    /// Writes immediately and waits (atomic). Used for edits, background and reader close.
    func saveNow() {
        guard writeProtection == nil else { return }
        saveWorkItem?.cancel()
        saveWorkItem = nil
        write(sync: true)
    }

    /// All writes go through one serial queue, so a newer snapshot can never be
    /// overwritten by an older one that was still in flight.
    private func write(sync: Bool) {
        guard writeProtection == nil else { return }
        books = capturingSyncChanges(books)
        let snapshot = books
        saveRevision += 1
        let revision = saveRevision
        let db = self.db
        let work = { () -> Error? in
            do { try db.save(snapshot); return nil } catch { return error }
        }
        if sync {
            if let e = writeQueue.sync(execute: work) { notice = ErrorMessages.explain(e).message }
            else { didPersist(snapshot, revision: revision) }
        } else {
            // LibraryStore lives as long as the app (it is the App's @StateObject) and,
            // being @MainActor, is Sendable: a plain strong capture is correct here.
            writeQueue.async {
                guard let e = work() else { onMain { self.didPersist(snapshot, revision: revision) }; return }
                onMain { self.notice = ErrorMessages.explain(e).message }
            }
        }
    }

    private func capturingSyncChanges(_ records: [BookRecord]) -> [BookRecord] {
        records.map { original in
            var book = original
            if var state = book.syncState { state.capture(book, device: syncDeviceID); book.syncState = state }
            return book
        }
    }

    private func didPersist(_ snapshot: [BookRecord], revision: UInt64) {
        guard revision >= persistedRevision else { return }
        persistedRevision = revision
        persistedBooks = snapshot
        cloudSync.localLibraryDidSave()
    }

    /// Commits incoming data together with every pending local edit before advancing
    /// CloudKit tokens. Failed disk writes leave both the UI and old tokens intact.
    func persistSyncedBook(_ record: BookRecord, replacing duplicateIDs: Set<UUID> = []) throws {
        var snapshot = books.filter { !duplicateIDs.contains($0.id) }
        if let index = snapshot.firstIndex(where: { $0.id == record.id }) { snapshot[index] = record }
        else { snapshot.append(record) }
        try commit(snapshot)
    }

    func isDownloaded(_ book: BookRecord) -> Bool {
        FileManager.default.fileExists(atPath: paths.archiveFile(book.id, format: book.format).path)
    }

    func acquireReaderLease(_ bookID: UUID) -> UUID {
        let lease = UUID(); readerLeases[lease] = bookID; return lease
    }
    func releaseReaderLease(_ lease: UUID) { readerLeases.removeValue(forKey: lease) }
    func hasActiveReader(_ bookID: UUID) -> Bool { readerLeases.values.contains(bookID) }

    // MARK: Storage info

    func storageUsage() async -> (books: Int64, caches: Int64) {
        let paths = self.paths
        return await Task.detached(priority: .utility) {
            (StorageMaintenance.directorySize(paths.booksDir), StorageMaintenance.directorySize(paths.cachesRoot))
        }.value
    }

    func clearCaches(except open: Set<UUID>) {
        let paths = self.paths
        DispatchQueue.global(qos: .utility).async { StorageMaintenance.clearCaches(paths: paths, except: open) }
    }
}
