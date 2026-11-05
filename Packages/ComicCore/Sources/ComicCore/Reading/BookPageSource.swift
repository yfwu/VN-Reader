import Foundation

/// Provides page bytes for one open book.
///
/// - ZIP and non-solid RAR: each page is read directly from the archive.
/// - Solid RAR: a background job decompresses the archive once, in order, into
///   a clearable disk cache (`Caches/Extracted/<id>/`). Requests for pages that
///   are not ready yet wait for the job (and can be cancelled).
public final class BookPageSource: @unchecked Sendable {
    public enum Preparation: Equatable, Sendable {
        case notNeeded
        case running(done: Int, total: Int)
        case complete
        case failed(ComicError)
    }

    public let bookID: UUID
    public let manifest: PageManifest
    public var pageCount: Int { manifest.pageCount }
    public var needsPreparation: Bool { solidCache != nil }

    /// Called (on a background queue) whenever preparation state changes.
    public var onPreparationChange: ((Preparation) -> Void)?

    private let archive: ComicArchive
    private let solidCache: SolidPageCache?
    private let readQueue = DispatchQueue(label: "vnreader.pages.read", qos: .userInitiated, attributes: .concurrent)

    public init(bookID: UUID, paths: LibraryPaths, format: ArchiveFormat,
                limits: ArchiveLimits = .default, diskSpace: DiskSpaceProviding = SystemDiskSpace()) throws {
        self.bookID = bookID
        let manifest = try PageManifestStore.read(paths.manifestFile(bookID))
        self.manifest = manifest
        self.archive = try ArchiveOpener.open(url: paths.archiveFile(bookID, format: format), limits: limits)
        if archive.isSolid {
            let archive = self.archive
            solidCache = SolidPageCache.obtain(dir: paths.extractedDir(bookID)) {
                SolidPageCache(dir: paths.extractedDir(bookID), manifest: manifest, archive: archive, diskSpace: diskSpace)
            }
        } else {
            solidCache = nil
        }
        solidCache?.onChange = { [weak self] state in self?.onPreparationChange?(state) }
    }

    public var preparation: Preparation { solidCache?.state ?? .notNeeded }

    /// Starts (or resumes) solid-archive extraction. No-op for random-access archives.
    public func startPreparation() { solidCache?.start() }

    /// Stops background work. Pages already extracted stay cached.
    public func close() { solidCache?.cancel() }

    /// Stops any background extraction for a book (used before deleting it).
    public static func stopBackgroundWork(bookID: UUID, paths: LibraryPaths) {
        SolidPageCache.cancelAndWait(dir: paths.extractedDir(bookID))
    }

    public func isPageReady(_ page: Int) -> Bool { solidCache?.isReady(page) ?? true }

    public func pageData(_ page: Int) async throws -> Data {
        guard manifest.pages.indices.contains(page) else { throw ComicError.entryNotFound(index: page) }
        if let cache = solidCache { return try await cache.data(for: page) }
        let index = manifest.pages[page].archiveIndex
        let archive = self.archive
        return try await withCheckedThrowingContinuation { cont in
            readQueue.async {
                do { cont.resume(returning: try archive.readEntry(at: index)) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    /// Synchronous variant for background callers (thumbnails, tests).
    public func pageDataSync(_ page: Int) throws -> Data {
        guard manifest.pages.indices.contains(page) else { throw ComicError.entryNotFound(index: page) }
        if let cache = solidCache { return try cache.dataSync(for: page) }
        return try archive.readEntry(at: manifest.pages[page].archiveIndex)
    }
}

final class SolidPageCache: @unchecked Sendable {
    let dir: URL
    let manifest: PageManifest
    let archive: ComicArchive
    let diskSpace: DiskSpaceProviding
    var onChange: ((BookPageSource.Preparation) -> Void)?

    private let lock = NSLock()
    private var ready: Set<Int> = []
    private var waiters: [Int: [UUID: CheckedContinuation<Data, Error>]] = [:]
    private var running = false
    private var cancelled = false
    private(set) var state: BookPageSource.Preparation
    private let pageForArchiveIndex: [Int: Int]

    init(dir: URL, manifest: PageManifest, archive: ComicArchive, diskSpace: DiskSpaceProviding) {
        self.dir = dir
        self.manifest = manifest
        self.archive = archive
        self.diskSpace = diskSpace
        var map: [Int: Int] = [:]
        for (i, p) in manifest.pages.enumerated() { map[p.archiveIndex] = i }
        pageForArchiveIndex = map
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        for i in manifest.pages.indices where fm.fileExists(atPath: SolidPageCache.file(dir, i).path) {
            ready.insert(i)
        }
        state = ready.count == manifest.pageCount ? .complete : .running(done: ready.count, total: manifest.pageCount)
        // Touch so LRU trimming sees recent use.
        try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: dir.path)
    }

    // A running extraction outlives the reader that started it; reopening the
    // same book reuses the job instead of starting a second one.
    private static let registryLock = NSLock()
    private static var running: [URL: SolidPageCache] = [:]

    static func obtain(dir: URL, make: () -> SolidPageCache) -> SolidPageCache {
        registryLock.lock(); defer { registryLock.unlock() }
        if let existing = running[dir] { return existing }
        return make()
    }

    /// Cancels a running extraction for `dir` and waits (bounded) until it stopped writing.
    static func cancelAndWait(dir: URL, timeout: TimeInterval = 5) {
        registryLock.lock()
        let c = running[dir]
        registryLock.unlock()
        guard let c else { return }
        c.cancel()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            registryLock.lock()
            let still = running[dir] === c
            registryLock.unlock()
            if !still { return }
            usleep(5_000)
        }
    }

    private static func register(_ c: SolidPageCache) {
        registryLock.lock(); running[c.dir] = c; registryLock.unlock()
    }

    private static func unregister(_ c: SolidPageCache) {
        registryLock.lock()
        if running[c.dir] === c { running[c.dir] = nil }
        registryLock.unlock()
    }

    static func file(_ dir: URL, _ page: Int) -> URL { dir.appendingPathComponent("\(page).page") }

    func isReady(_ page: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return ready.contains(page)
    }

    private func setState(_ s: BookPageSource.Preparation) {
        lock.lock(); state = s; lock.unlock()
        onChange?(s)
    }

    func start() {
        lock.lock()
        if running {
            cancelled = false
            lock.unlock()
            return
        }
        if ready.count == manifest.pageCount {
            let complete = ready.count == manifest.pageCount
            lock.unlock()
            if complete { setState(.complete) }
            return
        }
        running = true
        cancelled = false
        let missing = manifest.pages.indices.filter { !ready.contains($0) }
        lock.unlock()

        let needed = missing.reduce(Int64(0)) { $0 + Int64(manifest.pages[$1].size) }
        SolidPageCache.register(self)
        Thread.detachNewThread { [self] in
            Thread.current.qualityOfService = .userInitiated
            defer { SolidPageCache.unregister(self) }
            do {
                try DiskSpacePolicy.check(required: needed, at: dir, provider: diskSpace)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let wanted = Set(missing.map { manifest.pages[$0].archiveIndex })
                try archive.extractSequentially(indices: wanted) { archiveIndex, data in
                    guard let page = pageForArchiveIndex[archiveIndex] else { return true }
                    let target = SolidPageCache.file(dir, page)
                    let tmp = dir.appendingPathComponent("\(page).partial")
                    try data.write(to: tmp)
                    _ = try? FileManager.default.removeItem(at: target)
                    try FileManager.default.moveItem(at: tmp, to: target)
                    lock.lock()
                    ready.insert(page)
                    let w = waiters.removeValue(forKey: page) ?? [:]
                    let done = ready.count
                    let stop = cancelled
                    lock.unlock()
                    for c in w.values { c.resume(returning: data) }
                    setState(.running(done: done, total: manifest.pageCount))
                    return !stop
                }
                lock.lock()
                running = false
                let complete = ready.count == manifest.pageCount
                let wasCancelled = cancelled
                lock.unlock()
                if complete { setState(.complete) }
                else if wasCancelled { failWaiters(ComicError.cancelled, keepState: true) }
            } catch {
                let e = (error as? ComicError) ?? ComicError.ioError(detail: error.localizedDescription)
                lock.lock(); running = false; lock.unlock()
                failWaiters(e, keepState: false)
            }
        }
    }

    private func failWaiters(_ e: ComicError, keepState: Bool) {
        lock.lock()
        let all = waiters
        waiters = [:]
        lock.unlock()
        for (_, w) in all { for c in w.values { c.resume(throwing: e) } }
        if !keepState { setState(.failed(e)) }
    }

    func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
    }

    private func markMissing(_ page: Int) {
        lock.lock(); ready.remove(page); lock.unlock()
    }

    func dataSync(for page: Int) throws -> Data {
        if isReady(page) { return try Data(contentsOf: SolidPageCache.file(dir, page)) }
        throw ComicError.entryNotFound(index: page)
    }

    func data(for page: Int) async throws -> Data {
        if isReady(page) {
            if let d = try? Data(contentsOf: SolidPageCache.file(dir, page)) { return d }
            // File vanished (cache purged by the system): fall back to re-extraction.
            markMissing(page)
        }
        let token = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
                lock.lock()
                if ready.contains(page) {
                    lock.unlock()
                    do { cont.resume(returning: try Data(contentsOf: SolidPageCache.file(dir, page))) }
                    catch { cont.resume(throwing: error) }
                    return
                }
                if case .failed(let e) = state, !running {
                    lock.unlock()
                    cont.resume(throwing: e)
                    return
                }
                // onCancel may already have run (before this waiter existed).
                if Task.isCancelled {
                    lock.unlock()
                    cont.resume(throwing: CancellationError())
                    return
                }
                waiters[page, default: [:]][token] = cont
                let needsStart = !running
                lock.unlock()
                if needsStart { start() }
            }
        } onCancel: {
            lock.lock()
            let c = waiters[page]?.removeValue(forKey: token)
            lock.unlock()
            c?.resume(throwing: CancellationError())
        }
    }
}
