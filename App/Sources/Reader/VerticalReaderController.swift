import AVFoundation
import UIKit
import ComicCore

/// Continuous vertical scrolling (P1). Shares logical page numbers with the
/// pager; the "current page" is the page crossing the upper third of the screen.
final class VerticalReaderController: UIViewController, UITableViewDataSource, UITableViewDelegate, ReaderPaging {
    let model: ReaderViewModel
    private let table = UITableView(frame: .zero, style: .plain)
    private var aspect: [Int: CGFloat] = [:]   // height / width per page
    private var lastWidth: CGFloat = 0
    private var reportedPage = -1
    private var didInitialScroll = false
    private var passiveScrollDepth = 0
    private var isLayingOut = false
    private var userScrollActive = false
    private var userScrollReported = false

    init(model: ReaderViewModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = model.settings.background.uiColor
        table.backgroundColor = .clear
        table.separatorStyle = .none
        // Heights are explicit. Estimated offscreen rows make rect/offset
        // compensation unreliable when a delayed image changes an earlier row.
        table.estimatedRowHeight = 0
        table.dataSource = self
        table.delegate = self
        table.contentInsetAdjustmentBehavior = .never
        table.showsVerticalScrollIndicator = true
        table.register(VerticalPageCell.self, forCellReuseIdentifier: "page")
        table.frame = view.bounds
        table.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        table.accessibilityIdentifier = "reader.vertical"
        // Observe the existing recognizer without changing its delegate or input
        // behavior. UIScrollView's pan also receives trackpad and wheel events.
        table.panGestureRecognizer.addTarget(self, action: #selector(userPanChanged(_:)))
        view.addSubview(table)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        table.addGestureRecognizer(tap)
        table.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(longPressed(_:))))
        model.pager = self
    }

    @objc private func longPressed(_ press: UILongPressGestureRecognizer) { model.holdLoupe(press) }

    override func viewWillLayoutSubviews() {
        isLayingOut = true
        super.viewWillLayoutSubviews()
    }

    override func viewDidLayoutSubviews() {
        defer { isLayingOut = false }
        super.viewDidLayoutSubviews()
        if view.bounds.width != lastWidth, view.bounds.width > 0 {
            let page = model.currentPage
            lastWidth = view.bounds.width
            model.containerSizeChanged(view.bounds.size, scale: view.window?.screen.scale ?? traitCollection.displayScale)
            withPassiveScrolling {
                table.reloadData()
                table.layoutIfNeeded()
                scroll(to: page, userInitiated: false)
            }
            didInitialScroll = true
        }
    }

    private func height(for page: Int) -> CGFloat {
        (aspect[page] ?? 1.45) * max(view.bounds.width, 1)
    }

    private func withPassiveScrolling(_ operation: () -> Void) {
        passiveScrollDepth += 1
        defer { passiveScrollDepth -= 1 }
        operation()
    }

    private func scroll(to page: Int, userInitiated: Bool) {
        guard page >= 0, page < model.pageCount else { return }
        withPassiveScrolling {
            userScrollActive = false
            table.stopScrollingAndZooming()
            table.scrollToRow(at: IndexPath(row: page, section: 0), at: .top, animated: false)
        }
        reportCurrentPage(userInitiated: userInitiated, force: true)
    }

    // MARK: ReaderPaging

    func go(toPage page: Int, animated: Bool, userInitiated: Bool) { scroll(to: page, userInitiated: userInitiated) }

    func reloadForSettings() {
        let page = model.currentPage
        view.backgroundColor = model.settings.background.uiColor
        withPassiveScrolling {
            table.reloadData()
            table.layoutIfNeeded()
            scroll(to: page, userInitiated: false)
        }
    }

    func widePagesChanged() {}

    func pagesOnScreen() -> [PageOnScreen] {
        table.visibleCells.compactMap { ($0 as? VerticalPageCell)?.pageOnScreen }
    }

    // MARK: Table

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { model.pageCount }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        let page = indexPath.row
        // Resolve cached dimensions before UIKit lays out the row, without
        // starting a table update from inside cellForRowAt. Keep height(for:)
        // cache-free so a later decode can calculate its old-height correction.
        if aspect[page] == nil, let size = model.loader?.cachedImage(page)?.size, size.width > 0 {
            aspect[page] = size.height / size.width
        }
        return height(for: page)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "page", for: indexPath) as! VerticalPageCell
        let page = indexPath.row
        cell.configure(page: page, dark: model.settings.background.uiColor.isDark)
        cell.accessibilityCustomActions = [model.loupeAccessibilityAction]
        if let img = model.loader?.cachedImage(page) {
            cell.show(img)
        } else {
            cell.task = Task { @MainActor [weak self, weak cell] in
                guard let self, let loader = self.model.loader else { return }
                do {
                    let img = try await loader.image(for: page)
                    guard let cell, cell.page == page else { return }
                    cell.show(img)
                    self.updateAspect(page, img.size)
                } catch is CancellationError {
                } catch PageImageLoader.Failure.decode(let e) {
                    cell?.showError(e.title)
                } catch {
                    if !Task.isCancelled { cell?.showError(ErrorMessages.explain(error).title) }
                }
            }
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        (cell as? VerticalPageCell)?.task?.cancel()
    }

    private func updateAspect(_ page: Int, _ size: CGSize) {
        guard size.width > 0 else { return }
        let a = size.height / size.width
        if let old = aspect[page], abs(old - a) < 0.01 { return }
        let oldHeight = height(for: page)
        aspect[page] = a
        let delta = height(for: page) - oldHeight
        // Keep the visible content still when a page above the viewport changes height.
        let rowTop = table.rectForRow(at: IndexPath(row: page, section: 0)).minY
        withPassiveScrolling {
            UIView.performWithoutAnimation {
                table.beginUpdates()
                table.endUpdates()
                if rowTop < table.contentOffset.y {
                    table.contentOffset.y += delta
                }
            }
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard didInitialScroll else { return }
        let pan = scrollView.panGestureRecognizer.state
        let userInitiated = userScrollActive && (scrollView.isDragging || scrollView.isDecelerating || pan == .began || pan == .changed)
        reportCurrentPage(userInitiated: userInitiated)
    }

    private func beginUserScroll() {
        guard !userScrollActive, passiveScrollDepth == 0, !isLayingOut, model.pager === self else { return }
        userScrollActive = true
        userScrollReported = false
    }

    @objc private func userPanChanged(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began, .changed:
            beginUserScroll()
            if didInitialScroll { reportCurrentPage(userInitiated: userScrollActive) }
        case .ended:
            if didInitialScroll { reportCurrentPage(userInitiated: userScrollActive) }
            if !table.isDecelerating { userScrollActive = false }
        case .cancelled, .failed: userScrollActive = false
        default: break
        }
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { beginUserScroll() }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        reportCurrentPage(userInitiated: userScrollActive)
        if !decelerate { userScrollActive = false }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        reportCurrentPage(userInitiated: userScrollActive)
        userScrollActive = false
    }

    func scrollViewDidScrollToTop(_ scrollView: UIScrollView) {
        reportCurrentPage(userInitiated: true, force: true)
    }

    private func reportCurrentPage(userInitiated: Bool, force: Bool = false) {
        guard model.pager === self else { return }
        let userInitiated = userInitiated && passiveScrollDepth == 0 && !isLayingOut
        let probe = CGPoint(x: table.bounds.midX, y: table.contentOffset.y + table.bounds.height / 3)
        guard let ip = table.indexPathForRow(at: probe) else { return }
        // A passive correction may reveal a new row during an ongoing drag.
        // Its first subsequent user event must still persist that row.
        if ip.row != reportedPage { userScrollReported = false }
        if force || ip.row != reportedPage || (userInitiated && !userScrollReported) {
            reportedPage = ip.row
            if userInitiated { userScrollReported = true }
            model.pageDidChange(ip.row, visiblePages: [ip.row], userInitiated: userInitiated)
            model.loader?.prefetch(ReaderNavigation.prefetchOrder(around: ip.row, pageCount: model.pageCount))
        }
    }

    @objc private func tapped(_ g: UITapGestureRecognizer) {
        model.toggleChrome()
    }
}

final class VerticalPageCell: UITableViewCell {
    private let pageView = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let label = UILabel()
    var task: Task<Void, Never>?
    private(set) var page = -1

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        pageView.contentMode = .scaleAspectFit
        pageView.frame = contentView.bounds
        pageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(pageView)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.textAlignment = .center
        contentView.addSubview(spinner)
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            label.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            label.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.8),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .image
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(page: Int, dark: Bool) {
        task?.cancel()
        self.page = page
        pageView.image = nil
        label.text = nil
        label.textColor = dark ? .lightGray : .secondaryLabel
        spinner.color = dark ? .white : .gray
        spinner.startAnimating()
        accessibilityLabel = L10n.pageNumber(page + 1)
        accessibilityIdentifier = "reader.page.\(page)"
    }

    /// The cell can briefly be taller or shorter than its image, which then sits inside it.
    var pageOnScreen: PageOnScreen? {
        guard let image = pageView.image else { return nil }
        let drawn = AVMakeRect(aspectRatio: image.size, insideRect: pageView.bounds)
        return PageOnScreen(page: page, image: image, frame: pageView.convert(drawn, to: nil))
    }

    func show(_ image: UIImage) {
        spinner.stopAnimating()
        pageView.image = image
    }

    func showError(_ text: String) {
        spinner.stopAnimating()
        label.text = text
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        task?.cancel()
        task = nil
    }
}
