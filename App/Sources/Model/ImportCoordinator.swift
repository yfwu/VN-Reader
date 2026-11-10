import SwiftUI
import ComicCore

/// One file being imported (shown in the library until dismissed).
@MainActor
final class ImportJob: ObservableObject, Identifiable {
    enum State: Equatable {
        case waiting
        case downloading
        case working(ImportProgress)
        case failed(ErrorExplanation)
        case duplicate(String)
        case finished
    }

    let id = UUID()
    let fileName: String
    @Published var state: State = .waiting
    let cancelFlag = CancelFlag()

    init(fileName: String) { self.fileName = fileName }

    var isActive: Bool {
        switch state {
        case .waiting, .downloading, .working: return true
        default: return false
        }
    }
}

final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    private var onCancel: [() -> Void] = []
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func cancel() {
        lock.lock(); value = true; let handlers = onCancel; onCancel = []; lock.unlock()
        handlers.forEach { $0() }
    }
    func whenCancelled(_ f: @escaping () -> Void) {
        lock.lock()
        if value { lock.unlock(); f(); return }
        onCancel.append(f)
        lock.unlock()
    }
}

/// Imports files picked in the system document picker, opened from other apps
/// or dropped onto the library. Jobs run one at a time off the main thread.
@MainActor
final class ImportCoordinator: ObservableObject {
    @Published private(set) var jobs: [ImportJob] = []

    private let library: LibraryStore
    private let importer: BookImporter
    private let queue = DispatchQueue(label: "vnreader.import", qos: .userInitiated)
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid

    init(library: LibraryStore) {
        self.library = library
        self.importer = BookImporter(paths: library.paths, coverRenderer: ImageIOCoverRenderer())
    }

    var activeCount: Int { jobs.filter(\.isActive).count }

    /// - Parameter deleteAfterImport: for files the system copied into our own Inbox.
    func importFiles(_ urls: [URL], securityScoped: Bool, deleteAfterImport: Bool = false) {
        for url in urls {
            let job = ImportJob(fileName: url.lastPathComponent)
            jobs.append(job)
            if let protection = library.writeProtection {
                job.state = .failed(ErrorMessages.explain(protection))
                continue
            }
            enqueue(job, url: url, securityScoped: securityScoped, deleteAfterImport: deleteAfterImport)
        }
        updateBackgroundTask()
    }

    func cancel(_ job: ImportJob) { job.cancelFlag.cancel() }

    func dismiss(_ job: ImportJob) { jobs.removeAll { $0.id == job.id } }

    func dismissFinished() { jobs.removeAll { !$0.isActive } }

    /// Asks iPadOS for time to finish a big import when the user switches away. If the
    /// time runs out the app is suspended and the import continues when it comes back.
    private func updateBackgroundTask() {
        if activeCount == 0 {
            endBackgroundTask()
        } else if backgroundTask == .invalid {
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "vnreader.import") { [weak self] in
                MainActor.assumeIsolated { self?.endBackgroundTask() }
            }
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    private func enqueue(_ job: ImportJob, url: URL, securityScoped: Bool, deleteAfterImport: Bool) {
        let importer = self.importer
        let flag = job.cancelFlag
        queue.async { [weak self] in
            // Read the current library on the main thread (sequential jobs see earlier results).
            let existing: [BookRecord] = DispatchQueue.main.sync {
                MainActor.assumeIsolated { self?.library.books ?? [] }
            }
            let outcome = ImportCoordinator.run(importer: importer, url: url, securityScoped: securityScoped,
                                                existing: existing, flag: flag) { state in
                onMain { job.state = state }
            }
            // Wait for the durable library commit before the next queued import
            // reads its snapshot, and before deleting the system's Inbox copy.
            let committed = DispatchQueue.main.sync {
                MainActor.assumeIsolated { () -> Bool in
                    guard let self else { return false }
                    let committed = self.finish(job, outcome: outcome)
                    self.updateBackgroundTask()
                    return committed
                }
            }
            if deleteAfterImport && committed { try? FileManager.default.removeItem(at: url) }
        }
    }

    /// True only when a new import and its library record are both safely saved.
    private func finish(_ job: ImportJob, outcome: Result<ImportOutcome, Error>) -> Bool {
        switch outcome {
        case .success(.imported(let record)):
            do {
                try library.add(record)
                job.state = .finished
                jobs.removeAll { $0.id == job.id }
                return true
            } catch {
                // Keep both the completed managed copy and the Inbox source. A later
                // recovery may need either; startup never discards unknown book files.
                job.state = .failed(ErrorMessages.explain(error))
            }
        case .success(.duplicate(let id)):
            // Retain the Inbox copy: a stale record is not proof that its book file
            // is still present, so duplicate detection alone cannot authorize removal.
            job.state = .duplicate(library.book(id)?.displayName ?? "")
        case .failure(let error):
            if case ComicError.cancelled = error {
                jobs.removeAll { $0.id == job.id }
            } else {
                job.state = .failed(ErrorMessages.explain(error))
            }
        }
        return false
    }

    /// Runs on the import queue.
    nonisolated private static func run(importer: BookImporter, url: URL, securityScoped: Bool, existing: [BookRecord],
                                        flag: CancelFlag, report: @escaping (ImportJob.State) -> Void) -> Result<ImportOutcome, Error> {
        if flag.isCancelled { return .failure(ComicError.cancelled) }
        let scoped = securityScoped && url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        // Cloud files (iCloud Drive, other File Providers) may not be local yet.
        if let v = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]),
           let status = v.ubiquitousItemDownloadingStatus, status != .current {
            report(.downloading)
        }

        let coordinator = NSFileCoordinator()
        flag.whenCancelled { coordinator.cancel() }
        var coordError: NSError?
        var result: Result<ImportOutcome, Error> = .failure(ComicError.cancelled)
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordError) { readURL in
            result = Result {
                try importer.importBook(from: readURL, existing: existing, progress: { p in
                    report(.working(p))
                }, isCancelled: { flag.isCancelled })
            }
        }
        if let e = coordError {
            if flag.isCancelled || (e.domain == NSCocoaErrorDomain && e.code == NSUserCancelledError) {
                return .failure(ComicError.cancelled)
            }
            return .failure(ComicError.sourceUnreadable(detail: "\(e.localizedDescription) [\(e.domain) \(e.code)]"))
        }
        return result
    }
}

/// Runs `f` on the main queue, in order, with main-actor isolation.
func onMain(_ f: @escaping @MainActor () -> Void) {
    DispatchQueue.main.async { MainActor.assumeIsolated(f) }
}
