import UIKit
import ComicCore

/// A zoomable view that shows one page or a two-page spread.
///
/// Content is laid out at "base" size (pages normalised to a common height) and
/// zoomed with UIScrollView. The base zoom scale depends on the fit mode:
/// - fitPage: the whole spread is visible.
/// - fitWidth: the width fills the view; tall pages scroll vertically.
final class SpreadZoomView: UIScrollView, UIScrollViewDelegate {
    /// Called when the view moves between "at base zoom" and "zoomed in".
    var onZoomStateChange: ((Bool) -> Void)?

    private let container = UIView()
    private var imageViews: [UIImageView] = []
    private var aspectRatios: [CGFloat] = []   // width / height per page
    private(set) var fitMode: PageFitMode = .fitPage
    private var lastBoundsSize: CGSize = .zero
    private var wasZoomed = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        decelerationRate = .fast
        contentInsetAdjustmentBehavior = .never
        bouncesZoom = true
        alwaysBounceVertical = false
        alwaysBounceHorizontal = false
        addSubview(container)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// - Parameter screenOrder: images left-to-right on screen (nil = not loaded yet).
    func configure(images: [UIImage?], fitMode: PageFitMode) {
        self.fitMode = fitMode
        imageViews.forEach { $0.removeFromSuperview() }
        imageViews = images.map { img in
            let v = UIImageView(image: img)
            v.contentMode = .scaleAspectFit
            v.clipsToBounds = true
            v.accessibilityIgnoresInvertColors = true
            return v
        }
        imageViews.forEach(container.addSubview)
        aspectRatios = images.map { img in
            guard let s = img?.size, s.height > 0 else { return 0.7 }
            return s.width / s.height
        }
        layoutContent(resetZoom: true)
    }

    func setFitMode(_ mode: PageFitMode) {
        guard mode != fitMode else { return }
        fitMode = mode
        layoutContent(resetZoom: true)
    }

    var isZoomedIn: Bool { zoomScale > baseScale * 1.02 }

    /// The images and where they are drawn, in window coordinates.
    var drawnImages: [(image: UIImage, frame: CGRect)] {
        imageViews.compactMap { view in view.image.map { ($0, view.convert(view.bounds, to: nil)) } }
    }

    private var baseScale: CGFloat = 1

    private var baseContentSize: CGSize {
        let h: CGFloat = 1000
        let w = aspectRatios.reduce(0) { $0 + $1 * h }
        return CGSize(width: max(w, 1), height: h)
    }

    private func computeBaseScale() -> CGFloat {
        let c = baseContentSize
        guard bounds.width > 0, bounds.height > 0 else { return 1 }
        let fitPage = min(bounds.width / c.width, bounds.height / c.height)
        let fitWidth = bounds.width / c.width
        return fitMode == .fitPage ? fitPage : fitWidth
    }

    /// Lays the pages out at base size and returns to the fit zoom.
    private func layoutContent(resetZoom: Bool) {
        let c = baseContentSize
        minimumZoomScale = 1
        maximumZoomScale = 1
        zoomScale = 1
        container.frame = CGRect(origin: .zero, size: c)
        var x: CGFloat = 0
        for (i, v) in imageViews.enumerated() {
            let w = aspectRatios[i] * c.height
            v.frame = CGRect(x: x, y: 0, width: w, height: c.height)
            x += w
        }
        contentSize = c
        baseScale = computeBaseScale()
        if bounds.width > 0 {
            minimumZoomScale = min(baseScale, min(bounds.width / c.width, bounds.height / c.height))
        } else {
            minimumZoomScale = baseScale
        }
        maximumZoomScale = baseScale * 5
        zoomScale = baseScale
        centerContent()
        contentOffset = CGPoint(x: -contentInset.left, y: -contentInset.top)
        lastBoundsSize = bounds.size
        notifyZoomState()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != lastBoundsSize, bounds.width > 0 {
            // Rotation / window resize: keep "fit" if we were at fit.
            let wasAtBase = !isZoomedIn
            lastBoundsSize = bounds.size
            baseScale = computeBaseScale()
            let c = baseContentSize
            minimumZoomScale = min(baseScale, min(bounds.width / c.width, bounds.height / c.height))
            maximumZoomScale = baseScale * 5
            if wasAtBase {
                zoomScale = baseScale
                contentOffset = CGPoint(x: -contentInset.left, y: -contentInset.top)
            } else {
                zoomScale = min(max(zoomScale, minimumZoomScale), maximumZoomScale)
            }
            centerContent()
        }
    }

    func resetZoom(animated: Bool = false) {
        setZoomScale(baseScale, animated: animated)
        if !animated { contentOffset = CGPoint(x: -contentInset.left, y: -contentInset.top) }
        centerContent()
    }

    /// Double tap: zoom in around the point, or return to fit.
    func toggleZoom(at point: CGPoint) {
        if isZoomedIn {
            setZoomScale(baseScale, animated: true)
        } else {
            let target = min(baseScale * 2.5, maximumZoomScale)
            let p = container.convert(point, from: self)
            let size = CGSize(width: bounds.width / target, height: bounds.height / target)
            zoom(to: CGRect(x: p.x - size.width / 2, y: p.y - size.height / 2, width: size.width, height: size.height), animated: true)
        }
    }

    private func centerContent() {
        let w = contentSize.width, h = contentSize.height
        let insetX = max(0, (bounds.width - w) / 2)
        let insetY = max(0, (bounds.height - h) / 2)
        let inset = UIEdgeInsets(top: insetY, left: insetX, bottom: insetY, right: insetX)
        if contentInset != inset { contentInset = inset }
    }

    private func notifyZoomState() {
        let z = isZoomedIn
        if z != wasZoomed {
            wasZoomed = z
            onZoomStateChange?(z)
        }
    }

    // MARK: UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { container }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerContent()
        notifyZoomState()
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        notifyZoomState()
    }
}
