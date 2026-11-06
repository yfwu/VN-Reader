import SwiftUI
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

    let library: LibraryStore
    let settings: AppSettings
    weak var pager: ReaderPaging?
    private(set) var source: BookPageSource?
    private(set) var loader: PageImageLoader?
    private(set) var thumbnails: ThumbnailProvider?
    private var toastTask: Task<Void, Never>?
    private var pixelSize: CGSize = .zero

    var pageCount: Int { record.pageCount }
    var bookID: UUID { record.id }

    init(record: BookRecord, library: LibraryStore, settings: AppSettings = .shared) {
        self.record = record
        self.library = library
        self.settings = settings
        self.currentPage = max(0, min(record.progress.currentPage, record.pageCount - 1))
    }

    /// Opens the archive off the main thread.
    func open() {
        guard source == nil, openError == nil else { return }
        let paths = library.paths
        let id = record.id
        let format = record.format
        Task {
            do {
                let src = try await Task.detached(priority: .userInitiated) {
                    try BookPageSource(bookID: id, paths: paths, format: format)
                }.value
                self.attach(src)
            } catch {
                self.openError = ErrorMessages.explain(error)
            }
        }
    }

    private func attach(_ src: BookPageSource) {
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
        // Opening counts as reading (status becomes "reading", appears in Continue).
        library.recordPosition(record.id, page: currentPage)
        refreshRecord()
    }

    func containerSizeChanged(_ size: CGSize, scale: CGFloat) {
        loader?.updateTarget(CGSize(width: size.width * scale, height: size.height * scale))
    }

    private func refreshRecord() {
        if let r = library.book(record.id) { record = r }
    }

    // MARK: Paging

    func pageDidChange(_ page: Int, visiblePages: [Int]) {
        currentPage = page
        self.visiblePages = visiblePages
        // Store the last visible page of a spread so "finished" triggers on the final spread.
        library.recordPosition(record.id, page: visiblePages.max() == pageCount - 1 ? pageCount - 1 : page)
        refreshRecord()
    }

    func jump(to page: Int) {
        let p = max(0, min(page, pageCount - 1))
        pager?.go(toPage: p, animated: false)
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
        guard l != record.layout else { return }
        library.update(record.id, { $0.layout = l }, immediate: true)
        refreshRecord()
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

    // MARK: Lifecycle

    /// Persists the position right now (app going to background, view closing).
    func flush() { library.saveNow() }

    func close() {
        flush()
        loader?.cancelAll()
        thumbnails?.cancelAll()
        source?.close()
    }
}
