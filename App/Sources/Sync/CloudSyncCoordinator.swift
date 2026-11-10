import Foundation
import Combine
import CloudKit
import ComicCore
import UIKit

/// Opt-in, account-bound sync. The local library is authoritative for pending edits;
/// engine state is persisted only after received data has reached local storage.
@MainActor
final class CloudSyncCoordinator: ObservableObject {
    @Published private(set) var enabled: Bool
    @Published private(set) var busy = false
    @Published private(set) var status: String = L10n.syncOff { didSet { writeSmokeEvent() } }
    @Published private(set) var transferProgress: Double?
    @Published private(set) var activeTransfers: Set<UUID> = []
    private weak var library: LibraryStore?
    private var engine: CKSyncEngine?
    private var runTask: Task<Void, Never>?
    private var activeOperation: CKOperation?
    private var downloadOperations: [UUID: CKOperation] = [:]
    private var lastEnqueued: [String: BookSyncState] = [:]
    private var scheduledSync: Task<Void, Never>?
    private var followUpRequested = false
    private var knownUnboundBookIDs: Set<UUID> = []
    private var delegateError: Error?
    private var resolvedConflictRevision: UInt64 = 0
    private var halted = false
    private var applyingRemote = false
    private var persistFailed = false
    private var generation = UUID()
    private var state: SavedState
    private let stateFile: URL
    private var initializationError: Error?
    private lazy var container = CKContainer(identifier: "iCloud.org.yfwu.VNReader")
    private var database: CKDatabase { container.privateCloudDatabase }
    private static let metadataZone = CKRecordZone.ID(zoneName: CloudSyncEnvironment.zoneName("Library"), ownerName: CKCurrentUserDefaultName)

    struct SavedState: Codable {
        var version = 1
        var account: String?
        var engine: CKSyncEngine.State.Serialization?
        var systemFields: [String: Data] = [:]
        var uploadIDs: [String: String] = [:] // content ID → long-lived operation ID
    }

    init(library: LibraryStore) {
        self.library = library
        stateFile = library.paths.root.appendingPathComponent("cloud-sync-state.json")
        enabled = UserDefaults.standard.bool(forKey: CloudSyncEnvironment.defaultsPrefix + "enabled")
        state = SavedState()
        if FileManager.default.fileExists(atPath: stateFile.path) {
            do {
                state = try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: stateFile))
                guard state.version == 1 else { throw SyncFailure.invalidData }
            } catch {
                initializationError = error
                status = L10n.syncLocalFailure
            }
        }
    }

    private func writeSmokeEvent() {
        guard CloudSyncEnvironment.smokeRunID != nil, let library else { return }
        let file = library.paths.root.appendingPathComponent("smoke-events.log")
        let text = "\(ISO8601DateFormatter().string(from: Date())) SyncSmoke[\(CloudSyncEnvironment.smokeClientID)] \(status) books=\(library.books.count)\n"
        guard let data = text.data(using: .utf8) else { return }
        // Explicit DEBUG smoke launches can redirect stderr without granting tools
        // access to the sandbox library. Never emit book titles or account IDs.
        try? FileHandle.standardError.write(contentsOf: data)
        if FileManager.default.fileExists(atPath: file.path), let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd(); try? handle.write(contentsOf: data)
        } else { try? data.write(to: file, options: .atomic) }
    }

    /// Explicit smoke diagnostics contain error codes/counts only: never record
    /// payloads, system fields, record names, account identifiers, or userInfo text.
    private func smokeDiagnostic(_ message: String) {
        guard CloudSyncEnvironment.smokeRunID != nil else { return }
        let line = "\(ISO8601DateFormatter().string(from: Date())) SyncSmoke[\(CloudSyncEnvironment.smokeClientID)] diagnostic \(message)\n"
        if let data = line.data(using: .utf8) { try? FileHandle.standardError.write(contentsOf: data) }
    }

    private func smokeError(_ error: Error, stage: String, depth: Int = 0) {
        guard CloudSyncEnvironment.smokeRunID != nil, depth < 5 else { return }
        let value = error as NSError
        smokeDiagnostic("\(stage) error=\(value.domain):\(value.code)")
        if let nested = value.userInfo[NSUnderlyingErrorKey] as? Error {
            smokeError(nested, stage: stage + ".underlying", depth: depth + 1)
        }
        if let nested = value.userInfo["NSMultipleUnderlyingErrors"] as? [Error] {
            for (i, child) in nested.prefix(16).enumerated() {
                smokeError(child, stage: stage + ".multiple[\(i)]", depth: depth + 1)
            }
        }
        if let partial = value.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] {
            for (i, child) in partial.values.prefix(16).enumerated() {
                smokeError(child, stage: stage + ".partial[\(i)]", depth: depth + 1)
            }
        }
    }

    enum AutomaticSyncReason: String { case appOpened, appActive, bookOpened, bookClosed, readerForeground, importedBook }

    func startIfEnabled() { requestAutomaticSync(.appOpened) }

    /// App/reader lifecycle checkpoints share one trailing debounce. A checkpoint
    /// during an in-flight run requires one later fetch, never a parallel run.
    func requestAutomaticSync(_ reason: AutomaticSyncReason = .appActive) {
        guard enabled, !halted, !persistFailed else { return }
        smokeDiagnostic("auto request=\(reason.rawValue) disposition=\(busy ? "queued" : "debounced")")
        if busy { followUpRequested = true; return }
        scheduleAutomaticSync()
    }

    private func scheduleAutomaticSync() {
        scheduledSync?.cancel()
        let ticket = generation
        scheduledSync = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(500)) }
            catch { return }
            guard let self, self.generation == ticket, !Task.isCancelled,
                  self.enabled, !self.halted, !self.persistFailed else { return }
            self.scheduledSync = nil
            self.smokeDiagnostic("auto start")
            self.synchronize()
        }
    }

    private func cancelScheduledRequests() {
        scheduledSync?.cancel(); scheduledSync = nil
        followUpRequested = false
    }

    private func unboundLocalBookIDs() -> Set<UUID> {
        guard let library else { return [] }
        return Set(library.persistedBooks.filter { $0.syncState == nil && library.isDownloaded($0) }.map(\.id))
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        UserDefaults.standard.set(value, forKey: CloudSyncEnvironment.defaultsPrefix + "enabled")
        if value { synchronize() }
        else {
            generation = UUID()
            runTask?.cancel(); runTask = nil
            activeOperation?.cancel(); activeOperation = nil
            downloadOperations.values.forEach { $0.cancel() }; downloadOperations.removeAll()
            cancelScheduledRequests(); knownUnboundBookIDs.removeAll()
            let old = engine; engine = nil
            Task { await old?.cancelOperations() }
            busy = false; status = L10n.syncOff
        }
    }

    /// Called after a successful library save. Stamps live in that same snapshot,
    /// so a crash can always reconstruct pending work without a second outbox file.
    func localLibraryDidSave() {
        guard enabled, !applyingRemote, !halted, let library else { return }
        if let engine, let account = state.account {
            let ids = library.persistedBooks.compactMap { book -> CKSyncEngine.PendingRecordZoneChange? in
                guard let value = book.syncState, book.syncAccountID == account,
                      lastEnqueued[value.contentID] != value else { return nil }
                lastEnqueued[value.contentID] = value
                return .saveRecord(Self.bookID(value.contentID))
            }
            engine.state.add(pendingRecordZoneChanges: ids)
        }
        // Only newly seen local imports request a full cycle. Ordinary progress
        // saves already enqueue engine changes; completion/remote saves must not
        // create a loop for an unbound record whose archive is unavailable.
        let unbound = unboundLocalBookIDs()
        let newImports = unbound.subtracting(knownUnboundBookIDs)
        knownUnboundBookIDs = unbound
        if !newImports.isEmpty { requestAutomaticSync(.importedBook) }
    }

    func synchronize() {
        guard enabled else { return }
        guard !halted, !persistFailed else {
            status = explain(delegateError ?? SyncFailure.localPersistence)
            return
        }
        scheduledSync?.cancel(); scheduledSync = nil
        if busy { followUpRequested = true; return }
        followUpRequested = false
        knownUnboundBookIDs = unboundLocalBookIDs()
        let ticket = generation
        busy = true; delegateError = nil; status = L10n.syncWorking
        smokeDiagnostic("cycle start")
        runTask = Task {
            defer {
                if generation == ticket {
                    smokeDiagnostic("cycle finish result=\(status == L10n.syncCurrent ? "completed" : "failed") followUp=\(followUpRequested)")
                    runTask = nil
                    busy = false; transferProgress = nil; activeOperation = nil
                    if status == L10n.syncCurrent { localLibraryDidSave() }
                    if followUpRequested, enabled, !halted, !persistFailed {
                        followUpRequested = false
                        scheduleAutomaticSync()
                    }
                }
            }
            do {
                try await performSynchronization(ticket: ticket)
                try check(ticket)
                if let delegateError { throw delegateError }
                status = L10n.syncCurrent
            } catch {
                if generation == ticket, !(error is CancellationError) { status = explain(error) }
            }
        }
    }

    private func performSynchronization(ticket: UUID) async throws {
        var stage = "connect"
        do {
            guard initializationError == nil, !persistFailed else { throw SyncFailure.localPersistence }
            try await connect(ticket: ticket)
            stage = "prepare"
            try await prepareLocalBooks(ticket: ticket)
            configureEngine()
            guard let engine else { return }
            stage = "fetch"
            try await engine.fetchChanges(.init(scope: .zoneIDs([Self.metadataZone])))
            try check(ticket)
            localLibraryDidSave()
            stage = "send"
            smokeDiagnostic("send pending=\(engine.state.pendingRecordZoneChanges.count)")
            try await sendResolvingConflicts(ticket: ticket) { try await engine.sendChanges() }
            try check(ticket)
            stage = "resume-uploads"
            try await resumeUploads(ticket: ticket)
            stage = "upload-files"
            try await uploadLocalBooks(ticket: ticket)
        } catch {
            smokeError(error, stage: stage)
            throw error
        }
    }

    private func check(_ ticket: UUID) throws {
        try Task.checkCancellation()
        guard enabled, ticket == generation, !halted, !persistFailed else { throw CancellationError() }
    }

    /// sendChanges throws for a conflicted batch even after the delegate has
    /// durably merged its server records and requeued them. Await the replacement
    /// send before declaring completion; all other failures remain visible.
    private func sendResolvingConflicts(ticket: UUID, send: () async throws -> Void) async throws {
        for attempt in 0..<3 {
            let before = resolvedConflictRevision
            do {
                try await send()
                try check(ticket)
                return
            } catch {
                try check(ticket)
                guard attempt < 2, resolvedConflictRevision != before,
                      delegateError == nil, Self.containsOnlyRecordConflicts(error) else { throw error }
                smokeDiagnostic("retry resolved-conflict attempt=\(attempt + 2)")
            }
        }
    }

    private static func containsOnlyRecordConflicts(_ error: Error, depth: Int = 0) -> Bool {
        guard depth < 5 else { return false }
        let value = error as NSError
        guard value.domain == CKErrorDomain else { return false }
        if value.code == CKError.serverRecordChanged.rawValue { return true }
        guard value.code == CKError.partialFailure.rawValue,
              let partial = value.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error],
              !partial.isEmpty else { return false }
        return partial.values.allSatisfy { containsOnlyRecordConflicts($0, depth: depth + 1) }
    }

    private func connect(ticket: UUID) async throws {
        guard try await container.accountStatus() == .available else { throw SyncFailure.noAccount }
        let account = try await container.userRecordID().recordName
        try check(ticket)
        if let existing = state.account, existing != account { throw SyncFailure.accountChanged }
        if let library, library.books.contains(where: { $0.syncAccountID != nil && $0.syncAccountID != account }) {
            throw SyncFailure.accountChanged
        }
        state.account = account
        try persist()
        _ = try await database.save(CKRecordZone(zoneID: Self.metadataZone))
        _ = try await database.save(CKRecordZone(zoneID: CloudFileStore.zoneID))
        try check(ticket)
    }

    private func configureEngine() {
        if engine == nil {
            var config = CKSyncEngine.Configuration(database: database, stateSerialization: state.engine, delegate: self)
            config.automaticallySync = true
            engine = CKSyncEngine(config)
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    private func prepareLocalBooks(ticket: UUID) async throws {
        guard let library, let account = state.account else { return }
        for book in library.books where book.syncState == nil {
            try check(ticket)
            let url = library.paths.archiveFile(book.id, format: book.format)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            status = L10n.syncPreparing
            let hash = try await Self.hash(url)
            try check(ticket)
            guard var latest = library.book(book.id), latest.syncState == nil else { continue }
            var value = BookSyncState(contentID: hash, book: latest, device: library.syncDeviceID)
            let duplicates = library.books.filter { $0.id != latest.id && $0.syncAccountID == account && $0.syncState?.contentID == hash }
            guard !duplicates.contains(where: { library.hasActiveReader($0.id) }) else { throw SyncFailure.readerBusy }
            for duplicate in duplicates {
                if let other = duplicate.syncState {
                    value = other.mergedPreservingPendingChanges(with: value, localBook: duplicate, device: library.syncDeviceID)
                }
            }
            value.apply(to: &latest)
            latest.syncAccountID = account
            // Keep the full local archive's ID and preserve old duplicate folders;
            // only the redundant catalog row is consolidated after a durable save.
            try library.persistSyncedBook(latest, replacing: Set(duplicates.map(\.id)))
        }
        status = L10n.syncWorking
    }

    private func uploadLocalBooks(ticket: UUID) async throws {
        guard let library, let account = state.account else { return }
        for book in library.books {
            try check(ticket)
            guard let value = book.syncState, book.syncAccountID == account else { continue }
            try await verifyAccount(ticket: ticket)
            let file = library.paths.archiveFile(book.id, format: book.format)
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            if let remote = try await CloudFileStore.info(value.contentID, in: database) {
                guard CloudFileStore.matches(remote, contentID: value.contentID, size: book.fileSize) else { throw SyncFailure.invalidData }
                continue
            }
            // Upload only the immutable bytes that were hashed. Never replace an existing asset.
            let hash = try await Self.hash(file)
            guard hash == value.contentID else { throw SyncFailure.invalidData }
            try await verifyAccount(ticket: ticket)
            status = L10n.syncUploading
            activeTransfers.insert(book.id); transferProgress = 0
            defer { activeTransfers.remove(book.id) }
            let record = CloudFileStore.fileRecord(contentID: value.contentID, size: book.fileSize, file: file)
            let op = CKModifyRecordsOperation(recordsToSave: [record])
            op.savePolicy = .ifServerRecordUnchanged
            op.configuration.isLongLived = true
            op.configuration.allowsCellularAccess = false
            state.uploadIDs[value.contentID] = op.operationID
            try persist()
            try await executeUpload(op, contentID: value.contentID, ticket: ticket)
            state.uploadIDs.removeValue(forKey: value.contentID)
            try persist()
        }
    }

    private func resumeUploads(ticket: UUID) async throws {
        for (contentID, operationID) in state.uploadIDs {
            try check(ticket)
            if let op = try await container.longLivedOperation(for: operationID) as? CKModifyRecordsOperation {
                status = L10n.syncUploading
                try await executeUpload(op, contentID: contentID, ticket: ticket)
            }
            // Missing callbacks (including >24 h after completion) are reconciled by
            // inspecting the immutable server record in uploadLocalBooks, never blind overwrite.
            state.uploadIDs.removeValue(forKey: contentID)
            try persist()
        }
    }

    private func executeUpload(_ op: CKModifyRecordsOperation, contentID: String, ticket: UUID) async throws {
        activeOperation = op
        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    op.perRecordProgressBlock = { [weak self] _, value in
                        Task { @MainActor in if self?.generation == ticket { self?.transferProgress = value } }
                    }
                    op.modifyRecordsResultBlock = { result in continuation.resume(with: result) }
                    database.add(op)
                }
            } onCancel: { op.cancel() }
        } catch {
            try check(ticket)
            // Two devices may upload the same immutable content concurrently. If the
            // other upload won, verify its identity and treat this as success.
            guard let book = library?.books.first(where: { $0.syncState?.contentID == contentID }),
                  let remote = try? await CloudFileStore.info(contentID, in: database),
                  CloudFileStore.matches(remote, contentID: contentID, size: book.fileSize) else { throw error }
        }
        try check(ticket)
    }

    func ensureDownloaded(_ bookID: UUID, progress: @escaping @MainActor (Double) -> Void) async throws {
        guard let library, let book = library.book(bookID) else { throw SyncFailure.invalidData }
        let file = library.paths.archiveFile(bookID, format: book.format)
        if FileManager.default.fileExists(atPath: file.path) { return }
        guard enabled, let value = book.syncState, book.syncAccountID == state.account else { throw SyncFailure.downloadUnavailable }
        let ticket = generation
        if engine == nil { try await connect(ticket: ticket) }
        try await verifyAccount(ticket: ticket)
        try DiskSpacePolicy.check(required: book.fileSize, at: library.paths.root, provider: SystemDiskSpace())
        activeTransfers.insert(bookID)
        defer { activeTransfers.remove(bookID) }
        let id = CloudFileStore.recordID(value.contentID)
        let op = CKFetchRecordsOperation(recordIDs: [id])
        let downloadID = UUID()
        downloadOperations[downloadID] = op
        defer { downloadOperations.removeValue(forKey: downloadID) }
        op.configuration.allowsCellularAccess = false
        let record: CKRecord = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let box = DownloadResult()
                op.perRecordProgressBlock = { [weak self] _, fraction in Task { @MainActor in
                    guard self?.generation == ticket, self?.enabled == true, self?.halted == false else { return }
                    progress(fraction)
                } }
                op.perRecordResultBlock = { _, result in box.set(result) }
                op.fetchRecordsResultBlock = { result in
                    switch result {
                    case .failure(let error): continuation.resume(throwing: error)
                    case .success:
                        continuation.resume(with: box.get() ?? .failure(SyncFailure.downloadUnavailable))
                    }
                }
                database.add(op)
            }
        } onCancel: { op.cancel() }
        try check(ticket)
        guard CloudFileStore.matches(record, contentID: value.contentID, size: book.fileSize),
              let staged = (record["archive"] as? CKAsset)?.fileURL else { throw SyncFailure.invalidData }
        // Take ownership before the CloudKit staging file is reclaimed.
        let owned = library.paths.tempRoot.appendingPathComponent("download-" + UUID().uuidString)
        try FileManager.default.moveItem(at: staged, to: owned)
        defer { try? FileManager.default.removeItem(at: owned) }
        let hash = try await Self.hash(owned)
        try check(ticket)
        guard hash == value.contentID else { throw SyncFailure.invalidData }
        let manifestURL = library.paths.manifestFile(bookID)
        try await Task.detached(priority: .utility) {
            let archive = try ArchiveOpener.open(url: owned)
            let manifest = try PageManifestStore.read(manifestURL)
            guard manifest.pageCount == book.pageCount, manifest.format == archive.format,
                  manifest.pages.allSatisfy({ page in
                      archive.entries.indices.contains(page.archiveIndex)
                          && archive.entries[page.archiveIndex].path == page.path
                          && archive.entries[page.archiveIndex].uncompressedSize == page.size
                  }) else { throw SyncFailure.invalidData }
        }.value
        try check(ticket)
        guard library.book(bookID) != nil else { throw CancellationError() }
        if !FileManager.default.fileExists(atPath: file.path) { try FileManager.default.moveItem(at: owned, to: file) }
        library.objectWillChange.send()
    }

    func removeDownload(_ bookID: UUID) {
        guard enabled, let library, let book = library.book(bookID), let value = book.syncState,
              book.syncAccountID == state.account, !library.hasActiveReader(bookID), !activeTransfers.contains(bookID) else { return }
        let ticket = generation
        Task {
            do {
                try await verifyAccount(ticket: ticket)
                guard let remote = try await CloudFileStore.info(value.contentID, in: database),
                      CloudFileStore.matches(remote, contentID: value.contentID, size: book.fileSize) else { throw SyncFailure.downloadUnavailable }
                try check(ticket)
                guard !library.hasActiveReader(bookID), !activeTransfers.contains(bookID) else { return }
                let file = library.paths.archiveFile(bookID, format: book.format)
                try FileManager.default.removeItem(at: file)
                BookPageSource.stopBackgroundWork(bookID: bookID, paths: library.paths)
                try? FileManager.default.removeItem(at: library.paths.extractedDir(bookID))
                library.objectWillChange.send()
            } catch { status = explain(error) }
        }
    }

    nonisolated private static func hash(_ file: URL) async throws -> String {
        let task = Task.detached(priority: .utility) { try CloudFileStore.hashFile(file) }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    private func verifyAccount(ticket: UUID) async throws {
        guard try await container.accountStatus() == .available else { throw SyncFailure.noAccount }
        let current = try await container.userRecordID().recordName
        try check(ticket)
        guard state.account == current else { throw SyncFailure.accountChanged }
    }

    private static func bookID(_ contentID: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "book-" + contentID, zoneID: metadataZone)
    }

    private func cloudRecord(for id: CKRecord.ID) throws -> CKRecord? {
        guard let library, let account = state.account,
              let book = library.persistedBooks.first(where: { $0.syncState.map { Self.bookID($0.contentID) == id } ?? false }),
              book.syncAccountID == account, let value = book.syncState else { return nil }
        let record: CKRecord
        if let encoded = state.systemFields[id.recordName] {
            let decoder = try NSKeyedUnarchiver(forReadingFrom: encoded)
            decoder.requiresSecureCoding = true
            guard let restored = CKRecord(coder: decoder) else { throw SyncFailure.invalidData }
            decoder.finishDecoding(); record = restored
        } else { record = CKRecord(recordType: "Book", recordID: id) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let payload = try encoder.encode(CloudBookEnvelope(book: book, state: value))
        guard payload.count < 800_000 else { throw SyncFailure.invalidData }
        record["payload"] = payload as CKRecordValue
        record["manifest"] = CKAsset(fileURL: library.paths.manifestFile(book.id))
        if book.hasCover { record["cover"] = CKAsset(fileURL: library.paths.coverFile(book.id)) }
        return record
    }

    private func receive(_ record: CKRecord) async throws {
        let ticket = generation
        guard let library, let account = state.account,
              record.recordID.zoneID == Self.metadataZone, record.recordType == "Book",
              let data = record["payload"] as? Data, data.count < 800_000 else { throw SyncFailure.invalidData }
        let envelope = try JSONDecoder().decode(CloudBookEnvelope.self, from: data)
        guard envelope.isValid, record.recordID == Self.bookID(envelope.state.contentID) else { throw SyncFailure.invalidData }
        var existing = library.books.first(where: { $0.syncState?.contentID == envelope.state.contentID && $0.syncAccountID == account })
        if existing == nil {
            // An automatic fetch may race a newly completed local import. Verify the
            // candidate's full SHA before binding; CRC/size alone never establishes identity.
            let candidates = library.books.filter { $0.syncState == nil && $0.fingerprint == envelope.fingerprint && $0.fileSize == envelope.fileSize }
            for candidate in candidates {
                let file = library.paths.archiveFile(candidate.id, format: candidate.format)
                if try await Self.hash(file) == envelope.state.contentID {
                    try check(ticket)
                    guard state.account == account else { throw SyncFailure.accountChanged }
                    if var local = library.book(candidate.id) {
                        if let alreadyBound = local.syncState {
                            guard alreadyBound.contentID == envelope.state.contentID, local.syncAccountID == account else { continue }
                        } else {
                            local.syncState = BookSyncState(contentID: envelope.state.contentID, book: local, device: library.syncDeviceID)
                            local.syncAccountID = account
                        }
                        existing = local
                    }
                    break
                }
            }
        }
        try check(ticket)
        guard state.account == account else { throw SyncFailure.accountChanged }
        var book = existing ?? envelope.localRecord(account: account)
        if let local = book.syncState {
            guard local.version == envelope.state.version else { throw SyncFailure.invalidData }
            // Capture pending coalesced edits before applying the remote state.
            local.mergedPreservingPendingChanges(with: envelope.state, localBook: book, device: library.syncDeviceID).apply(to: &book)
        } else { envelope.state.apply(to: &book) }
        let fm = FileManager.default
        try fm.createDirectory(at: library.paths.bookDir(book.id), withIntermediateDirectories: true)
        let manifestURL = library.paths.manifestFile(book.id)
        if !fm.fileExists(atPath: manifestURL.path) {
            guard let source = (record["manifest"] as? CKAsset)?.fileURL else { throw SyncFailure.invalidData }
            let bytes = try Data(contentsOf: source)
            guard bytes.count < 8_000_000 else { throw SyncFailure.invalidData }
            let manifest = try JSONDecoder().decode(PageManifest.self, from: bytes)
            guard manifest.version == PageManifest.currentVersion, manifest.pageCount == book.pageCount,
                  manifest.format == book.format, manifest.pages.allSatisfy({ $0.archiveIndex >= 0 && $0.archiveIndex < 100_000 }) else { throw SyncFailure.invalidData }
            try bytes.write(to: manifestURL, options: .atomic)
        }
        if book.hasCover, !fm.fileExists(atPath: library.paths.coverFile(book.id).path) {
            guard let source = (record["cover"] as? CKAsset)?.fileURL else { throw SyncFailure.invalidData }
            let bytes = try Data(contentsOf: source)
            guard bytes.count <= 5_000_000 else { throw SyncFailure.invalidData }
            try bytes.write(to: library.paths.coverFile(book.id), options: .atomic)
        }
        applyingRemote = true
        defer { applyingRemote = false }
        try library.persistSyncedBook(book)
        let encoder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: encoder); encoder.finishEncoding()
        state.systemFields[record.recordID.recordName] = encoder.encodedData
        try persist()
        lastEnqueued[envelope.state.contentID] = envelope.state
        if book.syncState != envelope.state { engine?.state.add(pendingRecordZoneChanges: [.saveRecord(record.recordID)]) }
        // Enqueue other local edits that were durably flushed by persistSyncedBook.
        applyingRemote = false
        localLibraryDidSave()
    }

    private func persist() throws {
        do { try JSONEncoder().encode(state).write(to: stateFile, options: .atomic) }
        catch { persistFailed = true; throw SyncFailure.localPersistence }
    }

    private func stopAfterFailure(_ error: Error) {
        // Do not persist a newer change token after a local write/validation failure.
        smokeError(error, stage: "halt")
        halted = true; delegateError = error; status = explain(error)
        cancelScheduledRequests()
        generation = UUID(); runTask?.cancel(); activeOperation?.cancel()
        downloadOperations.values.forEach { $0.cancel() }; downloadOperations.removeAll()
        busy = false; transferProgress = nil
        let old = engine; engine = nil
        Task { await old?.cancelOperations() }
    }

    func explain(_ error: Error) -> String {
        if let e = error as? SyncFailure {
            switch e {
            case .noAccount: return L10n.syncNoAccount
            case .accountChanged: return L10n.syncAccountChanged
            case .downloadUnavailable: return L10n.syncWaitingForFile
            case .invalidData: return L10n.syncInvalidData
            case .localPersistence: return L10n.syncLocalFailure
            case .readerBusy: return L10n.syncReaderBusy
            }
        }
        if let e = error as? CKError {
            switch e.code {
            case .quotaExceeded: return L10n.syncQuota
            case .notAuthenticated, .accountTemporarilyUnavailable: return L10n.syncNoAccount
            case .unknownItem: return L10n.syncWaitingForFile
            case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy: return L10n.syncNetwork
            default: return L10n.syncFailed(e.localizedDescription)
            }
        }
        return L10n.syncFailed(error.localizedDescription)
    }
}

extension CloudSyncCoordinator: CKSyncEngineDelegate {
    nonisolated func nextFetchChangesOptions(_ context: CKSyncEngine.FetchChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.FetchChangesOptions {
        // Never fetch BookFiles (large assets), including on automatic background sync.
        .init(scope: .zoneIDs([await Self.metadataZone]))
    }

    nonisolated func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        await batch(context, engine: syncEngine)
    }

    private func batch(_ context: CKSyncEngine.SendChangesContext, engine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard enabled, !halted, !persistFailed else { return nil }
        let pending = engine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { [weak self] id in
            await self?.provide(id)
        }
    }

    private func provide(_ id: CKRecord.ID) -> CKRecord? {
        do { return try cloudRecord(for: id) }
        catch { stopAfterFailure(error); return nil }
    }

    nonisolated func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        await handle(event, from: syncEngine)
    }

    private func handle(_ event: CKSyncEngine.Event, from source: CKSyncEngine) async {
        guard enabled, !halted, !persistFailed, engine === source else { return }
        do {
            switch event {
            case .stateUpdate(let value): state.engine = value.stateSerialization; try persist()
            case .accountChange(let value):
                switch value.changeType {
                case .signIn(let user):
                    if state.account != user.recordName { throw SyncFailure.accountChanged }
                case .signOut, .switchAccounts: throw SyncFailure.accountChanged
                @unknown default: throw SyncFailure.accountChanged
                }
            case .fetchedRecordZoneChanges(let value):
                smokeDiagnostic("fetched modified=\(value.modifications.count) deleted=\(value.deletions.count)")
                for change in value.modifications { try await receive(change.record) }
                // Never delete local data merely because remote state disappeared.
                if !value.deletions.isEmpty { throw SyncFailure.invalidData }
            case .fetchedDatabaseChanges(let value):
                if value.deletions.contains(where: { $0.zoneID == Self.metadataZone }) { throw SyncFailure.invalidData }
            case .sentRecordZoneChanges(let value):
                smokeDiagnostic("sent saved=\(value.savedRecords.count) failed=\(value.failedRecordSaves.count)")
                for record in value.savedRecords { try await receive(record) }
                for failure in value.failedRecordSaves {
                    smokeError(failure.error, stage: "record-save")
                    if failure.error.code == .serverRecordChanged, let server = failure.error.serverRecord {
                        try await receive(server)
                        source.state.add(pendingRecordZoneChanges: [.saveRecord(server.recordID)])
                        resolvedConflictRevision &+= 1
                    } else { delegateError = failure.error; status = explain(failure.error) }
                }
            case .didFetchRecordZoneChanges(let value):
                if let error = value.error { smokeError(error, stage: "zone-fetch"); delegateError = error; status = explain(error) }
            case .sentDatabaseChanges(let value):
                if let error = value.failedZoneSaves.first?.error { smokeError(error, stage: "zone-save"); delegateError = error; status = explain(error) }
            default: break
            }
        } catch { stopAfterFailure(error) }
    }
}

enum SyncFailure: Error { case noAccount, accountChanged, downloadUnavailable, invalidData, localPersistence, readerBusy }

private final class DownloadResult: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Result<CKRecord, Error>?
    func set(_ result: Result<CKRecord, Error>) { lock.lock(); value = result; lock.unlock() }
    func get() -> Result<CKRecord, Error>? { lock.lock(); defer { lock.unlock() }; return value }
}
