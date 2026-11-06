import SwiftUI

/// A page as it appears on screen right now.
struct PageOnScreen {
    let page: Int
    let image: UIImage
    /// Where the image is drawn, in window coordinates.
    let frame: CGRect
}

struct LoupeOverlay: UIViewRepresentable {
    let model: ReaderViewModel
    func makeUIView(context: Context) -> LoupeOverlayView { LoupeOverlayView(model: model) }
    func updateUIView(_ view: LoupeOverlayView, context: Context) { view.updateAppearance() }
}

/// A round lens floating above the reader. It only takes touches on itself and its
/// controls, so the book underneath keeps working: pages still turn and scroll, and
/// the lens shows whatever passes beneath it. A long press on a page opens it (see
/// `ReaderViewModel.holdLoupe`), and it stays open until its close button is tapped.
///
/// The lens does not enlarge the screen. It draws the page again, from a bitmap decoded
/// at the file's full resolution, so it reveals detail the display-sized page lacks.
final class LoupeOverlayView: UIView {
    private static let presets: [CGFloat] = [1.5, 2.5, 4, 6]
    private static let magnificationRange: ClosedRange<CGFloat> = 1.5...6
    private static let minimumDiameter: CGFloat = 140
    private static let controlSize: CGFloat = 34

    private let model: ReaderViewModel
    private let lens = LensView()
    private let closeButton = LoupeControl(type: .system)
    private let zoomButton = LoupeControl(type: .system)
    private let resizeHandle = LoupeControl(type: .system)
    private var pageViews: [UIImageView] = []
    private var displayLink: CADisplayLink?
    private var lensCenter: CGPoint?
    private var diameter: CGFloat
    private var magnification: CGFloat
    private var grabOffset: CGFloat = 0

    init(model: ReaderViewModel) {
        self.model = model
        diameter = CGFloat(model.settings.loupeDiameter)
        magnification = CGFloat(model.settings.loupeMagnification)
        super.init(frame: .zero)
        semanticContentAttribute = .forceLeftToRight
        lens.accessibilityIdentifier = "reader.loupe.lens"
        lens.accessibilityLabel = L10n.loupe
        lens.onAdjust = { [weak self] up in self?.stepMagnification(up: up) }
        lens.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(moveLens(_:))))
        lens.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(pinchLens(_:))))
        addSubview(lens)

        closeButton.setSymbol("xmark")
        closeButton.accessibilityLabel = L10n.loupeHide
        closeButton.accessibilityIdentifier = "reader.loupe.close"
        closeButton.addAction(UIAction { [weak self] _ in self?.model.setLoupe(false) }, for: .touchUpInside)

        zoomButton.accessibilityIdentifier = "reader.loupe.zoom"
        zoomButton.addAction(UIAction { [weak self] _ in self?.nextPreset() }, for: .touchUpInside)

        resizeHandle.setSymbol("arrow.up.left.and.arrow.down.right")
        resizeHandle.accessibilityLabel = L10n.loupeResize
        resizeHandle.accessibilityIdentifier = "reader.loupe.resize"
        resizeHandle.accessibilityTraits = .adjustable
        resizeHandle.onAdjust = { [weak self] up in self?.stepDiameter(up: up) }
        resizeHandle.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(resizeLens(_:))))

        [zoomButton, resizeHandle, closeButton].forEach(addSubview)
        updateZoomLabel()
    }

    required init?(coder: NSCoder) { fatalError() }

    func updateAppearance() {
        lens.contentView.backgroundColor = model.settings.background.uiColor
    }

    /// Touches outside the lens and its controls go to the book underneath.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0 else { return }
        layoutLens()
    }

    private var maximumDiameter: CGFloat { max(Self.minimumDiameter, min(bounds.width, bounds.height) * 0.9) }

    private func layoutLens() {
        diameter = min(max(diameter, Self.minimumDiameter), maximumDiameter)
        if let hold = model.loupeHold {
            // Just above the finger, which would otherwise hide what the lens shows.
            let finger = convert(hold, from: nil)
            lensCenter = CGPoint(x: finger.x, y: finger.y - diameter / 2 - 28)
        }
        // The centre may reach the very edge, so the corners of a page can be inspected.
        let center = clamped(lensCenter ?? CGPoint(x: bounds.midX, y: bounds.midY), inset: 0)
        lensCenter = center
        lens.apply(center: center, diameter: diameter)
        closeButton.center = pointOnRim(degrees: 45, center: center)
        resizeHandle.center = pointOnRim(degrees: -45, center: center)
        zoomButton.center = pointOnRim(degrees: -90, center: center)
        render()
    }

    private func pointOnRim(degrees: CGFloat, center: CGPoint) -> CGPoint {
        let angle = degrees * .pi / 180
        return clamped(CGPoint(x: center.x + cos(angle) * diameter / 2, y: center.y - sin(angle) * diameter / 2),
                       inset: Self.controlSize / 2 + 6)
    }

    private func clamped(_ p: CGPoint, inset: CGFloat) -> CGPoint {
        CGPoint(x: min(max(p.x, inset), bounds.width - inset), y: min(max(p.y, inset), bounds.height - inset))
    }

    // MARK: Rendering

    override func didMoveToWindow() {
        super.didMoveToWindow()
        displayLink?.invalidate()
        displayLink = nil
        guard window != nil else { return }
        // Runs only while the lens is open: pages can move under it at any moment.
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func tick() {
        if model.loupeHold == nil { render() } else { layoutLens() }
    }

    private func render() {
        guard let lensCenter, window != nil else { return }
        let center = convert(lensCenter, to: nil)
        let radius = diameter / 2
        let sampled = CGRect(x: center.x - radius / magnification, y: center.y - radius / magnification,
                             width: diameter / magnification, height: diameter / magnification)
        let pages = (model.pager?.pagesOnScreen() ?? []).filter { $0.frame.intersects(sampled) }
        model.loader?.requestDetail(Set(pages.prefix(2).map(\.page)))

        while pageViews.count < pages.count {
            let view = UIImageView()
            view.contentMode = .scaleToFill
            view.accessibilityIgnoresInvertColors = true
            lens.contentView.addSubview(view)
            pageViews.append(view)
        }
        for (i, view) in pageViews.enumerated() {
            guard i < pages.count else {
                view.image = nil
                view.isHidden = true
                continue
            }
            let page = pages[i]
            let image = model.loader?.detailImage(page.page) ?? page.image
            if view.image !== image { view.image = image }
            view.isHidden = false
            view.frame = CGRect(x: (page.frame.minX - center.x) * magnification + radius,
                                y: (page.frame.minY - center.y) * magnification + radius,
                                width: page.frame.width * magnification,
                                height: page.frame.height * magnification)
        }
    }

    // MARK: Gestures

    @objc private func moveLens(_ g: UIPanGestureRecognizer) {
        guard let lensCenter else { return }
        let t = g.translation(in: self)
        self.lensCenter = CGPoint(x: lensCenter.x + t.x, y: lensCenter.y + t.y)
        g.setTranslation(.zero, in: self)
        layoutLens()
    }

    @objc private func pinchLens(_ g: UIPinchGestureRecognizer) {
        setMagnification(magnification * g.scale)
        g.scale = 1
        if g.state == .ended { save() }
    }

    @objc private func resizeLens(_ g: UIPanGestureRecognizer) {
        guard let lensCenter else { return }
        let p = g.location(in: self)
        let radius = hypot(p.x - lensCenter.x, p.y - lensCenter.y)
        if g.state == .began { grabOffset = radius - diameter / 2 }
        diameter = (radius - grabOffset) * 2
        layoutLens()
        if g.state == .ended { save() }
    }

    private func nextPreset() {
        setMagnification(Self.presets.first { $0 > magnification + 0.05 } ?? Self.presets[0])
        save()
    }

    private func stepMagnification(up: Bool) {
        setMagnification(magnification + (up ? 0.5 : -0.5))
        save()
    }

    private func stepDiameter(up: Bool) {
        diameter += up ? 40 : -40
        layoutLens()
        save()
    }

    private func setMagnification(_ value: CGFloat) {
        magnification = min(max(value, Self.magnificationRange.lowerBound), Self.magnificationRange.upperBound)
        updateZoomLabel()
        render()
    }

    private func updateZoomLabel() {
        let value = String(format: "%g", (magnification * 10).rounded() / 10)
        zoomButton.setText("\(value)×")
        zoomButton.accessibilityLabel = L10n.loupeMagnification(value)
        lens.accessibilityValue = L10n.loupeMagnification(value)
    }

    private func save() {
        model.settings.loupeDiameter = Double(diameter)
        model.settings.loupeMagnification = Double(magnification)
    }
}

/// The glass: a circle that clips its contents and is only touchable inside the circle.
private final class LensView: UIView {
    let contentView = UIView()
    var onAdjust: ((Bool) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.clipsToBounds = true
        contentView.layer.borderColor = UIColor(white: 1, alpha: 0.92).cgColor
        contentView.layer.borderWidth = 3
        addSubview(contentView)
        layer.borderColor = UIColor(white: 0, alpha: 0.35).cgColor
        layer.borderWidth = 0.5
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.45
        layer.shadowRadius = 14
        layer.shadowOffset = CGSize(width: 0, height: 6)
        isAccessibilityElement = true
        accessibilityTraits = [.adjustable]
    }

    required init?(coder: NSCoder) { fatalError() }

    func apply(center: CGPoint, diameter: CGFloat) {
        bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        self.center = center
        contentView.frame = bounds
        contentView.layer.cornerRadius = diameter / 2
        layer.cornerRadius = diameter / 2
        layer.shadowPath = UIBezierPath(ovalIn: bounds).cgPath
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        hypot(point.x - bounds.midX, point.y - bounds.midY) <= bounds.width / 2
    }

    override func accessibilityIncrement() { onAdjust?(true) }
    override func accessibilityDecrement() { onAdjust?(false) }
}

/// A small dark chip on the lens's rim, easier to hit than it looks.
private final class LoupeControl: UIButton {
    var onAdjust: ((Bool) -> Void)?

    func setSymbol(_ name: String) {
        configure { $0.image = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)) }
        bounds = CGRect(x: 0, y: 0, width: 34, height: 34)
    }

    func setText(_ text: String) {
        configure { config in
            config.attributedTitle = AttributedString(text, attributes: AttributeContainer([
                .font: UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold),
            ]))
        }
        bounds = CGRect(x: 0, y: 0, width: 56, height: 34)
    }

    private func configure(_ change: (inout UIButton.Configuration) -> Void) {
        var config = configuration ?? .filled()
        config.baseBackgroundColor = UIColor(white: 0.08, alpha: 0.88)
        config.baseForegroundColor = .white
        config.cornerStyle = .capsule
        config.contentInsets = .zero
        change(&config)
        configuration = config
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -8, dy: -8).contains(point)
    }

    override func accessibilityIncrement() { onAdjust?(true) }
    override func accessibilityDecrement() { onAdjust?(false) }
}
