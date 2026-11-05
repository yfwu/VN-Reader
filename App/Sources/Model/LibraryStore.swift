import SwiftUI
import ComicCore

/// The library: book records, persistence and storage housekeeping.
@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var books: [BookRecord] = []
    @Published var notice: String?

    let paths: LibraryPaths
    private let db: LibraryDatabase
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
        }
        // Interrupted imports / orphaned folders from a previous run. Synchronous on
        // purpose: it must finish before any import (e.g. a cold launch from "Open in…")
        // creates new staging or book folders that are not in this snapshot yet.
        StorageMaintenance.cleanUp(paths: paths, knownBooks: Set(books.map(\.id)))
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
        var list = books.filter { b in
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
        books.filter { $0.status == .reading }.max { ($0.progress.lastReadAt ?? .distantPast) < ($1.progress.lastReadAt ?? .distantPast) }
    }

    // MARK: Mutations

    func add(_ record: BookRecord) {
        var r = record
        let s = AppSettings.shared
        if r.metadata?.prefersRightToLeft != true { r.readingDirection = s.defaultDirection }
        r.fitMode = s.defaultFitMode
        r.layout = s.defaultLayout
        books.append(r)
        saveNow()
    }

    func update(_ id: UUID, _ change: (inout BookRecord) -> Void, immediate: Bool = false) {
        guard let i = books.firstIndex(where: { $0.id == id }) else { return }
        change(&books[i])
        immediate ? saveNow() : scheduleSave()
    }

    func rename(_ id: UUID, to name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }
        update(id, { $0.displayName = n }, immediate: true)
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
        let selected = books.filter { ids.contains($0.id) }
        let numbers = numberFrom.map { MetadataEditor.sequentialNumbers(for: selected, start: $0) } ?? [:]
        for i in books.indices where ids.contains(books[i].id) {
            var c = changes
            if let n = numbers[books[i].id] { c[.number] = n }
            MetadataEditor.apply(c, to: &books[i])
            if let style = nameStyle, let name = Self.generatedName(style, books[i].metadata) {
                books[i].displayName = name
            }
        }
        saveNow()
    }

    static func generatedName(_ style: BookNameStyle, _ metadata: ComicMetadata?) -> String? {
        guard let metadata else { return nil }
        return MetadataEditor.displayName(style: style, metadata: metadata, volumeFormat: L10n.volumeName)
    }

    func resetProgress(_ id: UUID) { update(id, { $0.resetProgress() }, immediate: true) }

    func markFinished(_ id: UUID) {
        update(id, { r in
            r.progress.finished = true
            r.progress.lastReadAt = r.progress.lastReadAt ?? Date()
        }, immediate: true)
    }

    func toggleFavorite(_ id: UUID) { update(id, { $0.isFavorite.toggle() }, immediate: true) }

    func recordPosition(_ id: UUID, page: Int) {
        update(id, { $0.recordPosition(page) })
    }

    func delete(_ id: UUID) {
        books.removeAll { $0.id == id }
        saveNow()
        CoverCache.shared.invalidate(paths.coverFile(id))
        let paths = self.paths
        DispatchQueue.global(qos: .utility).async { StorageMaintenance.deleteBook(id, paths: paths) }
    }

    func removeAllForTesting() {
        for b in books { StorageMaintenance.deleteBook(b.id, paths: paths) }
        books = []
        saveNow()
    }

    // MARK: Persistence

    /// Coalesces frequent updates (page turns) into one background write shortly after.
    private func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.write(sync: false) }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
    }

    /// Writes immediately and waits (atomic). Used for edits, background and reader close.
    func saveNow() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        write(sync: true)
    }

    /// All writes go through one serial queue, so a newer snapshot can never be
    /// overwritten by an older one that was still in flight.
    private func write(sync: Bool) {
        let snapshot = books
        let db = self.db
        let work = { () -> Error? in
            do { try db.save(snapshot); return nil } catch { return error }
        }
        if sync {
            if let e = writeQueue.sync(execute: work) { notice = ErrorMessages.explain(e).message }
        } else {
            // LibraryStore lives as long as the app (it is the App's @StateObject) and,
            // being @MainActor, is Sendable: a plain strong capture is correct here.
            writeQueue.async {
                guard let e = work() else { return }
                onMain { self.notice = ErrorMessages.explain(e).message }
            }
        }
    }

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
