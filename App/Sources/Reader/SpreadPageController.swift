import UIKit
import ComicCore

/// One screen of the pager: a single page or a spread, with loading and error states.
final class SpreadPageController: UIViewController, UIGestureRecognizerDelegate {
    let unit: Int
    let pages: [Int]          // logical reading order
    private weak var reader: ReaderViewController?
    private let zoomView = SpreadZoomView()
    private let spinner = UIActivityIndicatorView(style: .large)
    private let errorStack = UIStackView()
    private let errorTitle = UILabel()
    private let errorMessage = UILabel()
    private var loadTask: Task<Void, Never>?
    private let doubleTap = UITapGestureRecognizer()
    private let singleTap = UITapGestureRecognizer()

    init(unit: Int, pages: [Int], reader: ReaderViewController) {
        self.unit = unit
        self.pages = pages
        self.reader = reader
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { loadTask?.cancel() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.semanticContentAttribute = .forceLeftToRight
        zoomView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(zoomView)
        NSLayoutConstraint.activate([
            zoomView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            zoomView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            zoomView.topAnchor.constraint(equalTo: view.topAnchor),
            zoomView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        zoomView.onZoomStateChange = { [weak self] zoomed in
            guard let self else { return }
            self.reader?.pageZoomStateChanged(self, zoomed: zoomed)
        }
        zoomView.isAccessibilityElement = true
        zoomView.accessibilityTraits = [.image]
        zoomView.accessibilityLabel = pages.map { L10n.pageNumber($0 + 1) }.joined(separator: "、")
        zoomView.accessibilityIdentifier = "reader.page.\(pages.first ?? 0)"

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.color = .gray
        spinner.hidesWhenStopped = true
        view.addSubview(spinner)

        errorStack.axis = .vertical
        errorStack.spacing = 8
        errorStack.alignment = .center
        errorStack.translatesAutoresizingMaskIntoConstraints = false
        errorTitle.font = .preferredFont(forTextStyle: .headline)
        errorTitle.adjustsFontForContentSizeCategory = true
        errorMessage.font = .preferredFont(forTextStyle: .subheadline)
        errorMessage.adjustsFontForContentSizeCategory = true
        errorMessage.numberOfLines = 0
        errorMessage.textAlignment = .center
        let icon = UIImageView(image: UIImage(systemName: "exclamationmark.triangle"))
        icon.tintColor = .systemOrange
        icon.preferredSymbolConfiguration = .init(textStyle: .largeTitle)
        let retry = UIButton(configuration: .bordered())
        retry.configuration?.title = L10n.retry
        retry.addAction(UIAction { [weak self] _ in self?.load() }, for: .touchUpInside)
        [icon, errorTitle, errorMessage, retry].forEach(errorStack.addArrangedSubview)
        errorStack.isHidden = true
        view.addSubview(errorStack)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            errorStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            errorStack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            errorStack.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.8),
        ])

        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = self
        doubleTap.addTarget(self, action: #selector(handleDoubleTap(_:)))
        singleTap.numberOfTapsRequired = 1
        singleTap.addTarget(self, action: #selector(handleSingleTap(_:)))
        singleTap.require(toFail: doubleTap)
        // On the controller's view so taps also work over loading / error states.
        view.addGestureRecognizer(doubleTap)
        view.addGestureRecognizer(singleTap)
        applyAppearance()
        load()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        zoomView.resetZoom()
    }

    func applyAppearance() {
        guard let reader else { return }
        let bg = reader.backgroundColor
        view.backgroundColor = bg
        let dark = bg.isDark
        errorTitle.textColor = dark ? .white : .label
        errorMessage.textColor = dark ? UIColor(white: 0.8, alpha: 1) : .secondaryLabel
        spinner.color = dark ? .white : .gray
        zoomView.setFitMode(reader.fitMode)
    }

    var isZoomedIn: Bool { zoomView.isZoomedIn }

    func load() {
        guard let reader, let loader = reader.loader else { return }
        loadTask?.cancel()
        errorStack.isHidden = true
        let order = reader.screenOrder(pages)
        // Show cached pages immediately (no flash when paging back and forth).
        let cached = order.map { loader.cachedImage($0) }
        if cached.allSatisfy({ $0 != nil }) {
            zoomView.configure(images: cached, fitMode: reader.fitMode)
            spinner.stopAnimating()
            return
        }
        spinner.startAnimating()
        loadTask = Task { @MainActor [weak self] in
            var images: [UIImage?] = []
            var failure: ErrorExplanation?
            for p in order {
                do {
                    images.append(try await loader.image(for: p))
                } catch is CancellationError {
                    return
                } catch PageImageLoader.Failure.decode(let explanation) {
                    images.append(nil)
                    failure = explanation
                } catch {
                    if Task.isCancelled { return }
                    images.append(nil)
                    failure = ErrorMessages.explain(error)
                }
            }
            guard let self, !Task.isCancelled else { return }
            self.spinner.stopAnimating()
            let shown = images.compactMap { $0 }
            if shown.isEmpty, let f = failure {
                self.zoomView.configure(images: [], fitMode: self.reader?.fitMode ?? .fitPage)
                self.errorTitle.text = f.title
                self.errorMessage.text = f.message
                self.errorStack.isHidden = false
                self.zoomView.accessibilityLabel = f.title
            } else {
                self.zoomView.configure(images: shown, fitMode: self.reader?.fitMode ?? .fitPage)
                if let f = failure {
                    self.reader?.showToast(f.title)
                }
            }
        }
    }

    /// Double-tap zoom only starts in the centre zone (or anywhere while zoomed in),
    /// so taps on the side zones turn pages immediately, even in quick succession.
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard g === doubleTap else { return true }
        if zoomView.isZoomedIn { return true }
        let x = touch.location(in: view).x
        return ReaderNavigation.region(x: Double(x), width: Double(view.bounds.width)) == .center
    }

    @objc private func handleDoubleTap(_ g: UITapGestureRecognizer) {
        guard errorStack.isHidden else { return }
        zoomView.toggleZoom(at: g.location(in: zoomView))
    }

    @objc private func handleSingleTap(_ g: UITapGestureRecognizer) {
        guard let reader else { return }
        reader.handleTap(at: g.location(in: reader.view))
    }
}

extension UIColor {
    var isDark: Bool {
        var w: CGFloat = 0
        resolvedColor(with: UITraitCollection.current).getWhite(&w, alpha: nil)
        return w < 0.5
    }
}
