import SwiftUI
import Combine
import ComicCore

/// State of one open book. Owns the page source, image loader and thumbnails.
@MainActor
final class ReaderViewModel: ObservableObject {
    @Published private(set) var record: BookRecord
    @Published private(set) var currentPage: Int
    @Published private(set) var visiblePages: [Int] = []
    @Published private(set) var chromeVisible = false
    @Published private(set) var isReady = false
    @Published private(set) var openError: ErrorExplanation?
    @Published private(set) var preparation: BookPageSource.Preparation = .notNeeded
    @Published private(set) var toast: String?
    @Published private(set) var widePages: Set<Int> = []
    @Published private(set) var loupeVisible = false
    @Published private(set) var isPreparingShare = false
    /// Set while the share sheet is showing these files.
    @Published private(set) var sharedFiles: [URL]?

    let library: LibraryStore
    let settings: AppSettings
    weak var pager: ReaderPaging?
    private(set) var source: BookPageSource?
    private(set) var loader: PageImageLoader?
    private(set) var thumbnails: ThumbnailProvider?
    @Published private(set) var downloadProgress: Double?
    private var openTask: Task<Void, Never>?
    private var readerLease: UUID?
    private var toastTask: Task<Void, Never>?
    private var shareWork: Task<[URL], Error>?
    private var pixelSize: CGSize = .zero
    private var libraryObservation: AnyCancellable?
    private var hasNavigatedInForeground = false
    private var sceneIsActive = true
    private var wasBackgrounded = false
    private var hasClosed = false

    var pageCount: Int { record.pageCount }
    var bookID: UUID { record.id }
    var layout: PageLayout { settings.readerLayout(for: record) }

    init(record: BookRecord, library: LibraryStore, settings: AppSettings = .shared) {
        self.record = record
        self.library = library
        self.settings = settings
        self.currentPage = max(0, min(record.progress.currentPage, record.pageCount - 1))
        libraryObservation = library.$books.sink { [weak self] books in
            guard let self, let latest = books.first(where: { $0.id == self.bookID }) else { return }
            self.acceptLibraryRecord(latest)
        }
    }

    /// Opens the archive off the main thread.
    func open() {
        guard source == nil, openError == nil, openTask == nil else { return }
        hasClosed = false
        library.cloudSync.requestAutomaticSync(.bookOpened)
        readerLease = library.acquireReaderLease(record.id)
        let paths = library.paths
        let id = record.id
        let format = record.format
        openTask = Task {
            do {
                if !library.isDownloaded(record) {
                    downloadProgress = 0
                    try await library.cloudSync.ensureDownloaded(id) { value in self.downloadProgress = value }
                    downloadProgress = nil
                }
                try Task.checkCancellation()
                let src = try await Task.detached(priority: .userInitiated) {
                    try BookPageSource(bookID: id, paths: paths, format: format)
                }.value
                guard !Task.isCancelled else { src.close(); return }
                self.attach(src)
            } catch {
                guard !Task.isCancelled else { return }
                if record.syncState != nil {
                    self.openError = ErrorExplanation(title: L10n.syncTitle, message: library.cloudSync.explain(error))
                } else { self.openError = ErrorMessages.explain(error) }
            }
        }
    }

    private func attach(_ src: BookPageSource) {
        // A fetch/download may have updated the catalogue while the archive opened.
        if let latest = library.book(bookID) { acceptLibraryRecord(latest) }
        source = src
        // Decode for the longer screen side in both orientations so rotation is free.
        let screen = UIScreen.main.bounds.size
        let scale = UIScreen.main.scale
        let long = max(screen.width, screen.height) * scale
        pixelSize = CGSize(width: long, height: long)
        loader = PageImageLoader(source: src, targetPixelSize: pixelSize)
        loader?.onDecoded = { [weak self] page, size in self?.noteImageSize(page: page, size: size) }
        thumbnails = ThumbnailProvider(source: src, cacheDir: library.paths.thumbnailDir(record.id))
        src.onPreparationChange = { [weak self] state in
            onMain { self?.preparation = state }
        }
        preparation = src.preparation
        src.startPreparation()
        isReady = true
        // Recency is local presentation data, not a new cross-device position edit.
        library.recordOpened(bookID)
    }

    func containerSizeChanged(_ size: CGSize, scale: CGFloat) {
        loader?.updateTarget(CGSize(width: size.width * scale, height: size.height * scale))
    }

    private func refreshRecord() {
        if let r = library.book(record.id) { record = r }
    }

    private func acceptLibraryRecord(_ latest: BookRecord) {
        record = latest
        // Never move a reader who has started navigating in this foreground session.
        // On initial open/resume, keep following fetched progress until they do.
        guard sceneIsActive, !hasNavigatedInForeground else { return }
        let page = max(0, min(latest.progress.currentPage, max(0, latest.pageCount - 1)))
        guard currentPage != page else { return }
        currentPage = page
        visiblePages = []
        pager?.go(toPage: page, animated: false, userInitiated: false)
    }

    // MARK: Paging

    func pageDidChange(_ page: Int, visiblePages: [Int], userInitiated: Bool) {
        self.visiblePages = visiblePages
        // Initial display, re-pairing and settings/viewport changes are not reading
        // actions. In particular they must not stamp an old position as a new edit.
        guard userInitiated else { return }
        hasNavigatedInForeground = true
        currentPage = max(0, min(page, max(0, pageCount - 1)))
        library.recordPosition(record.id, page: currentPage,
                               reachedEnd: visiblePages.contains(pageCount - 1))
        refreshRecord()
    }

    func jump(to page: Int) {
        let p = max(0, min(page, pageCount - 1))
        pager?.go(toPage: p, animated: false, userInitiated: true)
    }

    var isCurrentPageReady: Bool {
        guard let source else { return false }
        return source.isPageReady(currentPage)
    }

    private func noteImageSize(page: Int, size: CGSize) {
        guard size.height > 0, size.width / size.height > 1.15, !widePages.contains(page) else { return }
        widePages.insert(page)
        pager?.widePagesChanged()
    }

    // MARK: Chrome & feedback

    func toggleChrome() { setChrome(!chromeVisible) }

    func setChrome(_ visible: Bool) {
        withAnimation(.easeOut(duration: 0.18)) { chromeVisible = visible }
    }

    /// Where a finger is holding the lens, in window coordinates, for as long as it does.
    /// A plain property: the lens reads it every frame, and may not exist yet on the first.
    private(set) var loupeHold: CGPoint?

    /// A long press on a page opens the lens, and the same press then moves it.
    func holdLoupe(_ press: UILongPressGestureRecognizer) {
        switch press.state {
        case .began, .changed:
            loupeHold = press.location(in: nil)
            if !loupeVisible { setLoupe(true) }
        default:
            loupeHold = nil
        }
    }

    /// VoiceOver's way to open the lens, which has no use for a long press.
    var loupeAccessibilityAction: UIAccessibilityCustomAction {
        UIAccessibilityCustomAction(name: L10n.loupeShow) { [weak self] _ in
            self?.setLoupe(true)
            return true
        }
    }

    /// Hides the toolbars when the lens opens, so the whole page is in view.
    func setLoupe(_ visible: Bool) {
        withAnimation(.easeOut(duration: 0.18)) {
            loupeVisible = visible
            if visible { chromeVisible = false }
        }
        if !visible { loader?.endDetail() }
    }

    func flash(_ text: String) {
        toastTask?.cancel()
        withAnimation(.easeOut(duration: 0.15)) { toast = text }
        UIAccessibility.post(notification: .announcement, argument: text)
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.2)) { self?.toast = nil }
        }
    }

    // MARK: Per-book settings

    func setDirection(_ d: ReadingDirection) {
        guard d != record.readingDirection else { return }
        library.update(record.id, { $0.readingDirection = d }, immediate: true)
        refreshRecord()
        pager?.reloadForSettings()
    }

    func setFitMode(_ m: PageFitMode) {
        guard m != record.fitMode else { return }
        library.update(record.id, { $0.fitMode = m }, immediate: true)
        refreshRecord()
        pager?.reloadForSettings()
    }

    func setLayout(_ l: PageLayout) {
        if settings.storeLocalReaderLayout(l, for: record.id) {
            // An explicit Mac choice stays local, even when it equals the current
            // effective layout. Keep it if the global default changes afterward.
            objectWillChange.send()
        } else {
            guard l != record.layout else { return }
            library.update(record.id, { $0.layout = l }, immediate: true)
            refreshRecord()
        }
        pager?.reloadForSettings()
    }

    func appSettingsChanged() { pager?.reloadForSettings() }

    var isBookmarked: Bool { record.bookmarks.contains(currentPage) }

    func toggleBookmark() {
        let p = currentPage
        library.update(record.id, { r in
            if let i = r.bookmarks.firstIndex(of: p) { r.bookmarks.remove(at: i) } else { r.bookmarks.append(p); r.bookmarks.sort() }
        }, immediate: true)
        refreshRecord()
        flash(isBookmarked ? L10n.addBookmark : L10n.removeBookmark)
    }

    // MARK: Sharing

    /// Shares what is on screen, which in a spread is both pages.
    func shareVisiblePages() {
        guard !isPreparingShare, sharedFiles == nil, let source else { return }
        let pages = (visiblePages.isEmpty ? [currentPage] : visiblePages).sorted()
        let bookName = record.displayName
        isPreparingShare = true
        let work = Task.detached(priority: .userInitiated) {
            try await SharedPageFiles.write(pages: pages, source: source, bookName: bookName)
        }
        shareWork = work
        Task {
            defer {
                isPreparingShare = false
                shareWork = nil
            }
            do {
                sharedFiles = try await work.value
            } catch {
                if !work.isCancelled { flash(L10n.shareFailed) }
            }
        }
    }

    func shareDidEnd() { sharedFiles = nil }

    // MARK: Lifecycle

    /// Persists the position right now (app going to background, view closing).
    func flush() { library.saveNow() }

    func scenePhaseChanged(_ phase: ScenePhase) {
        if phase == .active {
            guard !sceneIsActive else { return }
            sceneIsActive = true
            // Transient inactive states (system sheets/menus) can request fresh
            // metadata without resetting the active reader's navigation policy.
            if wasBackgrounded { hasNavigatedInForeground = false; wasBackgrounded = false }
            if let latest = library.book(bookID) { acceptLibraryRecord(latest) }
            library.cloudSync.requestAutomaticSync(.readerForeground)
        } else {
            sceneIsActive = false
            if phase == .background { wasBackgrounded = true }
            flush()
        }
    }

    func close() {
        guard !hasClosed else { return }
        hasClosed = true
        openTask?.cancel(); openTask = nil
        libraryObservation?.cancel(); libraryObservation = nil
        if let readerLease { library.releaseReaderLease(readerLease); self.readerLease = nil }
        flush()
        library.cloudSync.requestAutomaticSync(.bookClosed)
        shareWork?.cancel()
        SharedPageFiles.removeAll()
        loader?.cancelAll()
        thumbnails?.cancelAll()
        source?.close()
    }
}
