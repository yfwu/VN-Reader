import UIKit
import ComicCore

/// Horizontal pager built on UIPageViewController.
///
/// The logical page list is never reversed. Reading direction only decides which
/// neighbour the pager shows on the right / left and which way taps and swipes go.
/// Commands the view model sends to whichever reading view is active.
@MainActor
protocol ReaderPaging: AnyObject {
    func go(toPage page: Int, animated: Bool, userInitiated: Bool)
    func reloadForSettings()
    func widePagesChanged()
    func pagesOnScreen() -> [PageOnScreen]
}

final class ReaderViewController: UIViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate, ReaderPaging {
    let model: ReaderViewModel
    private var pageVC: UIPageViewController!
    /// Screens in reading order; each holds 1 page or a 2-page spread.
    private(set) var units: [[Int]] = []
    private var currentUnit = 0
    private var isTransitioning = false
    private var transitionID: UUID?
    private var interactiveTransitionID: UUID?
    private var pendingPage: (page: Int, userInitiated: Bool)?
    private var lastLayoutSize: CGSize = .zero

    var loader: PageImageLoader? { model.loader }
    var fitMode: PageFitMode { model.record.fitMode }
    var direction: ReadingDirection { model.record.readingDirection }
    var backgroundColor: UIColor { model.settings.background.uiColor }

    init(model: ReaderViewModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = backgroundColor
        // Comic reading direction is independent from the UI language direction.
        view.semanticContentAttribute = .forceLeftToRight
        pageVC = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal,
                                      options: [.interPageSpacing: 12])
        pageVC.dataSource = self
        pageVC.delegate = self
        pageVC.view.semanticContentAttribute = .forceLeftToRight
        pageVC.view.backgroundColor = .clear
        addChild(pageVC)
        pageVC.view.frame = view.bounds
        pageVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(pageVC.view)
        pageVC.didMove(toParent: self)
        pagerScrollView?.semanticContentAttribute = .forceLeftToRight
        view.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(longPressed(_:))))
        rebuildUnits(size: view.bounds.size)
        showUnit(unitIndex(containing: model.currentPage), animated: false, focusedPage: model.currentPage, userInitiated: false)
        model.pager = self
    }

    @objc private func longPressed(_ press: UILongPressGestureRecognizer) { model.holdLoupe(press) }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let size = view.bounds.size
        guard size != lastLayoutSize, size.width > 0 else { return }
        let changedSpreadMode = prefersSpreads(size: size) != prefersSpreads(size: lastLayoutSize)
        lastLayoutSize = size
        model.containerSizeChanged(size, scale: view.window?.screen.scale ?? traitCollection.displayScale)
        if changedSpreadMode { rebuildPreservingPage() }
    }

    // MARK: Units (single pages or spreads)

    var usesSpreads: Bool {
        prefersSpreads(size: view.bounds.size)
    }

    private func prefersSpreads(size: CGSize) -> Bool {
        guard model.layout == .double else { return false }
#if targetEnvironment(macCatalyst)
        return true
#else
        return size.width > size.height
#endif
    }

    private func rebuildUnits(size: CGSize) {
        let count = model.pageCount
        if prefersSpreads(size: size) {
            let layout = SpreadLayout(pageCount: count, coverAlone: model.settings.coverAlone,
                                      shift: model.settings.shiftSpreads, widePages: model.widePages)
            units = layout.spreads.map(\.pages)
        } else {
            units = (0..<count).map { [$0] }
        }
    }

    private func unitIndex(containing page: Int) -> Int {
        units.firstIndex { $0.contains(page) } ?? 0
    }

    /// Left-to-right screen order of a unit's pages.
    func screenOrder(_ pages: [Int]) -> [Int] {
        direction == .leftToRight ? pages : pages.reversed()
    }

    private func makeController(_ unit: Int) -> SpreadPageController? {
        guard units.indices.contains(unit) else { return nil }
        return SpreadPageController(unit: unit, pages: units[unit], reader: self)
    }

    /// An image can finish decoding after its original pairing became obsolete.
    /// Neighbour controllers are valid too, but known wide pages must stand alone.
    func canDisplay(_ controller: SpreadPageController) -> Bool {
        units.indices.contains(controller.unit) && units[controller.unit] == controller.pages &&
        (controller.pages.count == 1 || Set(controller.pages).isDisjoint(with: model.widePages))
    }

    private var pagerScrollView: UIScrollView? {
        pageVC?.view.subviews.compactMap { $0 as? UIScrollView }.first
    }

    // MARK: Navigation

    private func showUnit(_ unit: Int, animated: Bool, focusedPage: Int? = nil, userInitiated: Bool) {
        guard let vc = makeController(unit) else { return }
        let page = focusedPage.flatMap { vc.pages.contains($0) ? $0 : nil } ?? vc.pages.first ?? 0
        guard !isTransitioning else { queuePage(page, userInitiated: userInitiated); return }
        let forward = unit >= currentUnit
        // LTR: the next screen enters from the right (.forward). RTL: from the left.
        let nav: UIPageViewController.NavigationDirection = (forward == (direction == .leftToRight)) ? .forward : .reverse
        let animate = animated && !isTransitioning && model.settings.animatePageTurns && view.window != nil
        currentUnit = unit
        if animate {
            isTransitioning = true
            let id = UUID()
            transitionID = id
            pageVC.setViewControllers([vc], direction: nav, animated: true) { [weak self] _ in
                self?.finishTransition(id, focusedPage: page, userInitiated: false)
            }
        } else {
            pageVC.setViewControllers([vc], direction: nav, animated: false)
        }
        pagerScrollView?.isScrollEnabled = !animate
        unitDidChange(focusedPage: page, userInitiated: userInitiated)
    }

    /// Keep the old unit map stable until UIKit finishes the transition. Rebuild
    /// from the latest sizes/settings, never reinstall a captured old controller.
    private func finishTransition(_ id: UUID, focusedPage: Int, userInitiated: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.transitionID == id, self.model.pager === self else { return }
            self.transitionID = nil
            self.isTransitioning = false
            // A completed user swipe takes priority over a remote restore queued
            // while it was in flight. An explicit queued user jump still wins.
            let pending = self.pendingPage
            let navigation = userInitiated && pending?.userInitiated != true
                ? (page: focusedPage, userInitiated: true)
                : pending ?? (page: focusedPage, userInitiated: userInitiated)
            self.pendingPage = nil
            self.rebuildUnits(size: self.view.bounds.size)
            self.showUnit(self.unitIndex(containing: navigation.page), animated: false, focusedPage: navigation.page, userInitiated: navigation.userInitiated)
        }
    }

    private func unitDidChange(focusedPage: Int? = nil, userInitiated: Bool) {
        guard units.indices.contains(currentUnit) else { return }
        let pages = units[currentUnit]
        let page = focusedPage.flatMap { pages.contains($0) ? $0 : nil } ?? pages.first ?? 0
        model.pageDidChange(page, visiblePages: pages, userInitiated: userInitiated)
        prefetch()
    }

    private func prefetch() {
        guard let loader else { return }
        var pages: [Int] = units[currentUnit]
        for d in [1, 2, -1] {
            let u = currentUnit + d
            if units.indices.contains(u) { pages += units[u] }
        }
        loader.prefetch(pages)
    }

    func go(toPage page: Int, animated: Bool, userInitiated: Bool) {
        let page = max(0, min(page, model.pageCount - 1))
        guard !isTransitioning else { queuePage(page, userInitiated: userInitiated); return }
        let u = unitIndex(containing: page)
        if u == currentUnit { unitDidChange(focusedPage: page, userInitiated: userInitiated); return }
        showUnit(u, animated: animated && abs(u - currentUnit) == 1, focusedPage: page, userInitiated: userInitiated)
    }

    private func queuePage(_ page: Int, userInitiated: Bool) {
        // A remote update cannot displace an explicit jump awaiting animation.
        guard userInitiated || pendingPage?.userInitiated != true else { return }
        pendingPage = (page, userInitiated)
    }

    func perform(_ action: ReaderNavigation.Action) {
        switch action {
        case .toggleChrome:
            model.toggleChrome()
        case .next:
            guard !isTransitioning else { return }
            if currentUnit + 1 < units.count { showUnit(currentUnit + 1, animated: true, userInitiated: true) } else { model.flash(L10n.lastPage) }
        case .previous:
            guard !isTransitioning else { return }
            if currentUnit > 0 { showUnit(currentUnit - 1, animated: true, userInitiated: true) } else { model.flash(L10n.firstPage) }
        }
    }

    func handleTap(at point: CGPoint) {
        let region = ReaderNavigation.region(x: Double(point.x), width: Double(view.bounds.width))
        if region != .center && !model.settings.tapToTurn {
            model.toggleChrome()
            return
        }
        let action = ReaderNavigation.action(for: region, direction: direction)
        if action != .toggleChrome && model.chromeVisible { model.setChrome(false) }
        perform(action)
    }

    /// Wide (already two-page) images were discovered: re-pair spreads in place.
    func widePagesChanged() {
        guard usesSpreads else { return }
        rebuildPreservingPage()
    }

    private func rebuildPreservingPage(force: Bool = false) {
        // finishTransition always uses the newest layout, wide pages and viewport.
        guard !isTransitioning else { return }
        let page = model.currentPage
        let before = units
        rebuildUnits(size: view.bounds.size)
        guard force || units != before else { return }
        showUnit(unitIndex(containing: page), animated: false, focusedPage: page, userInitiated: false)
    }

    /// Re-applies direction / fit / layout / background without leaving the current page.
    func reloadForSettings() {
        view.backgroundColor = backgroundColor
        rebuildPreservingPage(force: true)
    }

    func pageZoomStateChanged(_ page: SpreadPageController, zoomed: Bool) {
        guard pageVC.viewControllers?.first === page else { return }
        // While zoomed in, drags pan the image instead of turning pages.
        pagerScrollView?.isScrollEnabled = !isTransitioning && !zoomed
    }

    func showToast(_ text: String) { model.flash(text) }

    /// Includes the neighbour sliding in during a swipe, which is also a child of the pager.
    func pagesOnScreen() -> [PageOnScreen] {
        pageVC.children.compactMap { $0 as? SpreadPageController }.flatMap(\.pagesOnScreen)
    }

    // MARK: UIPageViewControllerDataSource

    func pageViewController(_ pvc: UIPageViewController, viewControllerBefore vc: UIViewController) -> UIViewController? {
        guard let c = vc as? SpreadPageController else { return nil }
        // "Before" = the screen to the left.
        return makeController(direction == .leftToRight ? c.unit - 1 : c.unit + 1)
    }

    func pageViewController(_ pvc: UIPageViewController, viewControllerAfter vc: UIViewController) -> UIViewController? {
        guard let c = vc as? SpreadPageController else { return nil }
        return makeController(direction == .leftToRight ? c.unit + 1 : c.unit - 1)
    }

    // MARK: UIPageViewControllerDelegate

    func pageViewController(_ pvc: UIPageViewController, willTransitionTo pending: [UIViewController]) {
        let id = UUID()
        transitionID = id
        interactiveTransitionID = id
        isTransitioning = true
    }

    func pageViewController(_ pvc: UIPageViewController, didFinishAnimating finished: Bool,
                            previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        guard let id = interactiveTransitionID else { return }
        interactiveTransitionID = nil
        let visible = pvc.viewControllers?.first as? SpreadPageController
        let page = completed ? (visible?.pages.first ?? model.currentPage) : model.currentPage
        finishTransition(id, focusedPage: page, userInitiated: completed)
    }

    // MARK: Hardware keyboard

    override var keyCommands: [UIKeyCommand]? {
        let left = UIKeyCommand(input: UIKeyCommand.inputLeftArrow, modifierFlags: [], action: #selector(keyLeft))
        let right = UIKeyCommand(input: UIKeyCommand.inputRightArrow, modifierFlags: [], action: #selector(keyRight))
        let space = UIKeyCommand(input: " ", modifierFlags: [], action: #selector(keyNext))
        [left, right, space].forEach { $0.wantsPriorityOverSystemBehavior = true }
        return [left, right, space]
    }

    override var canBecomeFirstResponder: Bool { true }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    @objc private func keyLeft() { perform(ReaderNavigation.action(for: .left, direction: direction)) }
    @objc private func keyRight() { perform(ReaderNavigation.action(for: .right, direction: direction)) }
    @objc private func keyNext() { perform(.next) }
}
