import UIKit
import ComicCore

/// Horizontal pager built on UIPageViewController.
///
/// The logical page list is never reversed. Reading direction only decides which
/// neighbour the pager shows on the right / left and which way taps and swipes go.
/// Commands the view model sends to whichever reading view is active.
@MainActor
protocol ReaderPaging: AnyObject {
    func go(toPage page: Int, animated: Bool)
    func reloadForSettings()
    func widePagesChanged()
}

final class ReaderViewController: UIViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate, ReaderPaging {
    let model: ReaderViewModel
    private var pageVC: UIPageViewController!
    /// Screens in reading order; each holds 1 page or a 2-page spread.
    private(set) var units: [[Int]] = []
    private var currentUnit = 0
    private var isTransitioning = false
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
        rebuildUnits(size: view.bounds.size)
        showUnit(unitIndex(containing: model.currentPage), animated: false)
        model.pager = self
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let size = view.bounds.size
        guard size != lastLayoutSize, size.width > 0 else { return }
        let changedOrientation = (size.width > size.height) != (lastLayoutSize.width > lastLayoutSize.height)
        lastLayoutSize = size
        model.containerSizeChanged(size, scale: view.window?.screen.scale ?? traitCollection.displayScale)
        if changedOrientation && model.record.layout == .double {
            let page = model.currentPage
            rebuildUnits(size: size)
            showUnit(unitIndex(containing: page), animated: false)
        }
    }

    // MARK: Units (single pages or spreads)

    var usesSpreads: Bool {
        model.record.layout == .double && view.bounds.width > view.bounds.height
    }

    private func rebuildUnits(size: CGSize) {
        let count = model.pageCount
        if model.record.layout == .double && size.width > size.height {
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

    private var pagerScrollView: UIScrollView? {
        pageVC?.view.subviews.compactMap { $0 as? UIScrollView }.first
    }

    // MARK: Navigation

    private func showUnit(_ unit: Int, animated: Bool) {
        guard let vc = makeController(unit) else { return }
        let forward = unit >= currentUnit
        // LTR: the next screen enters from the right (.forward). RTL: from the left.
        let nav: UIPageViewController.NavigationDirection = (forward == (direction == .leftToRight)) ? .forward : .reverse
        let animate = animated && !isTransitioning && model.settings.animatePageTurns && view.window != nil
        currentUnit = unit
        if animate {
            isTransitioning = true
            pageVC.setViewControllers([vc], direction: nav, animated: true) { [weak self] _ in
                guard let self else { return }
                self.isTransitioning = false
                // Work around UIPageViewController keeping stale neighbours after
                // programmatic animated transitions.
                DispatchQueue.main.async { self.pageVC.setViewControllers([vc], direction: nav, animated: false) }
            }
        } else {
            pageVC.setViewControllers([vc], direction: nav, animated: false)
        }
        pagerScrollView?.isScrollEnabled = true
        unitDidChange()
    }

    private func unitDidChange() {
        guard units.indices.contains(currentUnit) else { return }
        model.pageDidChange(units[currentUnit].first ?? 0, visiblePages: units[currentUnit])
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

    func go(toPage page: Int, animated: Bool) {
        let u = unitIndex(containing: max(0, min(page, model.pageCount - 1)))
        guard u != currentUnit else { return }
        showUnit(u, animated: animated && abs(u - currentUnit) == 1)
    }

    func perform(_ action: ReaderNavigation.Action) {
        switch action {
        case .toggleChrome:
            model.toggleChrome()
        case .next:
            if currentUnit + 1 < units.count { showUnit(currentUnit + 1, animated: true) } else { model.flash(L10n.lastPage) }
        case .previous:
            if currentUnit > 0 { showUnit(currentUnit - 1, animated: true) } else { model.flash(L10n.firstPage) }
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
        guard model.record.layout == .double, view.bounds.width > view.bounds.height else { return }
        let before = units
        rebuildUnits(size: view.bounds.size)
        guard units != before else { return }
        let page = model.currentPage
        currentUnit = unitIndex(containing: page)
        if let vc = makeController(currentUnit) {
            pageVC.setViewControllers([vc], direction: .forward, animated: false)
        }
        unitDidChange()
    }

    /// Re-applies direction / fit / layout / background without leaving the current page.
    func reloadForSettings() {
        let page = model.currentPage
        view.backgroundColor = backgroundColor
        rebuildUnits(size: view.bounds.size)
        let u = unitIndex(containing: page)
        currentUnit = u
        if let vc = makeController(u) {
            pageVC.setViewControllers([vc], direction: .forward, animated: false)
        }
        pagerScrollView?.isScrollEnabled = true
        unitDidChange()
    }

    func pageZoomStateChanged(_ page: SpreadPageController, zoomed: Bool) {
        guard pageVC.viewControllers?.first === page else { return }
        // While zoomed in, drags pan the image instead of turning pages.
        pagerScrollView?.isScrollEnabled = !zoomed
    }

    func showToast(_ text: String) { model.flash(text) }

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
        isTransitioning = true
    }

    func pageViewController(_ pvc: UIPageViewController, didFinishAnimating finished: Bool,
                            previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        isTransitioning = false
        guard completed, let c = pvc.viewControllers?.first as? SpreadPageController else { return }
        currentUnit = c.unit
        pagerScrollView?.isScrollEnabled = !c.isZoomedIn
        unitDidChange()
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
