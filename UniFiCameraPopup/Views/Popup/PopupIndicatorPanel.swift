import AppCore
import AppKit

/// Hover bar and remaining-time line of one miniature (docs/design/popup-miniatur.md). Both lie
/// outside the popup, so they get their own borderless, transparent window that ignores the mouse
/// and follows the popup's frame (same animations, see `MiniatureStackPresenter`).
///
/// The panel covers the popup frame plus `inset` on every side; the popup sits centered in it.
final class PopupIndicatorPanel: NSPanel {
    /// Room around the popup: hover bar 5 + 4 at the inner side, line 4 + 3 below.
    static let inset: CGFloat = 12

    private let indicatorView: IndicatorView

    init(side: PopupAnchor.Horizontal) {
        indicatorView = IndicatorView(side: side)
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        contentView = indicatorView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    static func frame(around popupFrame: NSRect) -> NSRect {
        popupFrame.insetBy(dx: -inset, dy: -inset)
    }

    var side: PopupAnchor.Horizontal {
        get { indicatorView.side }
        set { indicatorView.side = newValue }
    }

    /// Hover started: the track fades in (50 ms), the fill runs from top to bottom (500 ms, linear).
    func startHoverBar() { indicatorView.startHoverBar() }

    /// Hover ended or the popup grows: fade out (50 ms) or at once; the fill is reset.
    func stopHoverBar(animated: Bool) { indicatorView.stopHoverBar(animated: animated) }

    func showRest(_ state: MiniatureRestIndicator) { indicatorView.showRest(state) }
}

private final class IndicatorView: NSView {
    private static let barWidth: CGFloat = 4
    private static let barGap: CGFloat = 5
    private static let lineHeight: CGFloat = 3
    private static let lineGap: CGFloat = 4
    private static let yellow = NSColor(srgbRed: 1, green: 0xD8 / 255.0, blue: 0x4D / 255.0, alpha: 1).cgColor
    private static let track = NSColor(white: 1, alpha: 0.18).cgColor
    private static let lineColor = NSColor(white: 1, alpha: 0.75).cgColor

    var side: PopupAnchor.Horizontal { didSet { layoutLayers() } }

    private let trackLayer = CALayer()
    private let fillLayer = CALayer()
    private let lineLayer = CALayer()
    private var rest = MiniatureRestIndicator.neutral
    private var hoverActive = false

    init(side: PopupAnchor.Horizontal) {
        self.side = side
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        trackLayer.backgroundColor = Self.track
        trackLayer.cornerRadius = 2
        trackLayer.masksToBounds = true
        trackLayer.opacity = 0
        fillLayer.backgroundColor = Self.yellow
        // Grows from the top edge (layer coordinates are y-up here).
        fillLayer.anchorPoint = CGPoint(x: 0.5, y: 1)
        trackLayer.addSublayer(fillLayer)

        lineLayer.cornerRadius = 1.5
        lineLayer.backgroundColor = Self.lineColor
        lineLayer.opacity = 0

        layer?.addSublayer(trackLayer)
        layer?.addSublayer(lineLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutLayers()
    }

    /// The popup's rectangle inside the panel.
    private var popupRect: CGRect {
        bounds.insetBy(dx: PopupIndicatorPanel.inset, dy: PopupIndicatorPanel.inset)
    }

    private func layoutLayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let popup = popupRect
        let barX = side == .leading ? popup.maxX + Self.barGap : popup.minX - Self.barGap - Self.barWidth
        trackLayer.frame = CGRect(x: barX, y: popup.minY, width: Self.barWidth, height: max(popup.height, 0))
        fillLayer.bounds = CGRect(x: 0, y: 0, width: Self.barWidth, height: hoverActive ? trackLayer.bounds.height : 0)
        fillLayer.position = CGPoint(x: Self.barWidth / 2, y: trackLayer.bounds.height)
        layoutLine()
        CATransaction.commit()
    }

    /// Shrinks towards the outer edge.
    private func layoutLine() {
        let popup = popupRect
        let width = max(0, popup.width * CGFloat(rest.lineFraction))
        let x = side == .leading ? popup.minX : popup.maxX - width
        lineLayer.frame = CGRect(x: x, y: popup.minY - Self.lineGap - Self.lineHeight, width: width, height: Self.lineHeight)
    }

    func startHoverBar() {
        hoverActive = true
        let height = trackLayer.bounds.height
        CATransaction.begin()
        CATransaction.setAnimationDuration(MiniatureTiming.hoverBarFade)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .linear))
        trackLayer.opacity = 1
        CATransaction.commit()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fillLayer.removeAllAnimations()
        fillLayer.bounds.size.height = height
        CATransaction.commit()
        let fill = CABasicAnimation(keyPath: "bounds.size.height")
        fill.fromValue = 0
        fill.toValue = height
        fill.duration = MiniatureTiming.hover
        fill.timingFunction = CAMediaTimingFunction(name: .linear)
        fillLayer.add(fill, forKey: "fill")
    }

    func stopHoverBar(animated: Bool) {
        hoverActive = false
        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(MiniatureTiming.hoverBarFade)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .linear))
        } else {
            CATransaction.setDisableActions(true)
            trackLayer.removeAllAnimations()
        }
        trackLayer.opacity = 0
        CATransaction.commit()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fillLayer.removeAllAnimations()
        fillLayer.bounds.size.height = 0
        CATransaction.commit()
    }

    func showRest(_ state: MiniatureRestIndicator) {
        guard state != rest else { return }
        rest = state
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        lineLayer.opacity = state.lineVisible ? 1 : 0
        lineLayer.backgroundColor = state.lineWarning ? Self.yellow : Self.lineColor
        layoutLine()
        CATransaction.commit()
    }
}
