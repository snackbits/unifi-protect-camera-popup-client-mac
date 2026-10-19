import AppCore
import SwiftUI

/// Animated illustration of a popup layout (Einstellungen › Erscheinungsbild › Popup-Layout).
/// Proposal A „Desktop-Szene“ of `docs/design/mockups/einstellungen-erscheinungsbild.html`:
/// geometry in % of the tile (`cq` = 1 % of the width), keyframes and 7 s cycle from the mock CSS.
/// The scene colors are fixed (illustration); ring and texts around it come from the tokens.
struct PopupLayoutPreview: View {
    let mode: PopupLayoutMode
    /// Popups on the left edge (`PopupPosition.left`): popups, pointer and hover bar mirrored.
    var mirrored = false
    /// Start of the cycle (both tiles share it, so they run in step).
    var start = Date()
    /// Fixed point in the cycle (0…1) instead of the clock, e.g. for snapshots.
    var fixedProgress: Double?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let cycle: TimeInterval = 7

    /// Still frame: miniature 2 enlarged with its overlays (or both full popups).
    /// Equals the mock's resting state, used for „Bewegung reduzieren“.
    static func restProgress(for mode: PopupLayoutMode) -> Double {
        mode == .miniature ? 0.55 : 0.5
    }

    var body: some View {
        Group {
            if let still = fixedProgress ?? (reduceMotion ? Self.restProgress(for: mode) : nil) {
                PopupLayoutScene(mode: mode, progress: still, mirrored: mirrored)
            } else {
                TimelineView(.animation) { context in
                    let elapsed = max(0, context.date.timeIntervalSince(start))
                    PopupLayoutScene(
                        mode: mode,
                        progress: elapsed.truncatingRemainder(dividingBy: Self.cycle) / Self.cycle,
                        mirrored: mirrored
                    )
                }
            }
        }
        .aspectRatio(16.0 / 10.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityHidden(true)
    }
}

/// One frame of the illustration at `progress` (0…1 of the 7 s cycle).
struct PopupLayoutScene: View {
    let mode: PopupLayoutMode
    let progress: Double
    var mirrored = false

    var body: some View {
        Canvas { context, size in
            let scene = SceneGeometry(size: size, mirrored: mirrored)
            scene.drawDesktop(in: context)
            let p = progress * 100
            switch mode {
            case .miniature: scene.drawMiniatures(in: context, at: p)
            case .full: scene.drawFullPopups(in: context, at: p)
            }
        }
    }
}

// MARK: - Keyframes

/// Timing curves between two keyframes (CSS cubic-bezier).
private enum Curve {
    case linear, ease, easeIn, easeOut, easeInOut

    private var points: (Double, Double, Double, Double) {
        switch self {
        case .linear: return (0, 0, 1, 1)
        case .ease: return (0.25, 0.1, 0.25, 1)
        case .easeIn: return (0.42, 0, 1, 1)
        case .easeOut: return (0, 0, 0.58, 1)
        case .easeInOut: return (0.42, 0, 0.58, 1)
        }
    }

    func callAsFunction(_ x: Double) -> Double {
        if case .linear = self { return x }
        let (x1, y1, x2, y2) = points
        func bezier(_ t: Double, _ a: Double, _ b: Double) -> Double {
            let u = 1 - t
            return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t
        }
        // Solve x(t) = x by bisection (monotonic for these curves).
        var low = 0.0, high = 1.0, t = x
        for _ in 0..<24 {
            t = (low + high) / 2
            if bezier(t, x1, x2) < x { low = t } else { high = t }
        }
        return bezier(t, y1, y2)
    }
}

/// Keyframe track: stops at percent of the cycle; `curve` shapes the segment that ends at the stop.
private struct Track {
    struct Stop {
        let at: Double
        let value: Double
        var curve: Curve = .ease
    }

    let stops: [Stop]

    init(_ stops: [(Double, Double, Curve)]) {
        self.stops = stops.map { Stop(at: $0.0, value: $0.1, curve: $0.2) }
    }

    func value(at p: Double) -> Double {
        guard let first = stops.first else { return 0 }
        if p <= first.at { return first.value }
        for (a, b) in zip(stops, stops.dropFirst()) where p <= b.at {
            guard b.at > a.at else { return b.value }
            let u = (p - a.at) / (b.at - a.at)
            return a.value + (b.value - a.value) * b.curve(u)
        }
        return stops.last?.value ?? 0
    }
}

/// Keyframes of the mock (`@keyframes m1/m2/m3/ov/cur/hb/hbf/f1/f2`). Slide-in eases out, slide-out
/// eases in, growing and shrinking ease in and out (as the real popups); the hover fill is linear
/// (spec: 500 ms linear). Everything else keeps the CSS default `ease`.
private enum Keys {
    // Miniature 1: translateX(135 %) → none.
    static let m1Shift = Track([(0, 135, .ease), (7, 0, .easeOut), (82, 0, .ease), (91, 135, .easeIn), (100, 135, .ease)])
    // Miniature 2: slides in, grows (40–46 %), shrinks (64–70 %), slides out.
    static let m2Shift = Track([(0, 135, .ease), (9, 135, .ease), (16, 0, .easeOut), (84, 0, .ease),
                                (93, 135, .easeIn), (100, 135, .ease)])
    static let m2Grow = Track([(0, 0, .ease), (40, 0, .ease), (46, 1, .easeInOut), (64, 1, .ease),
                               (70, 0, .easeInOut), (100, 0, .ease)])
    // Miniature 3: slides in, is pushed down to --t3e while 2 is big, back up, slides out.
    static let m3Shift = Track([(0, 135, .ease), (16, 135, .ease), (23, 0, .easeOut), (86, 0, .ease),
                                (95, 135, .easeIn), (100, 135, .ease)])
    static let m3Top = Track([(0, 47, .ease), (40, 47, .ease), (46, 69.8, .easeInOut), (64, 69.8, .ease),
                              (70, 47, .easeInOut), (100, 47, .ease)])
    // Overlays of the enlarged miniature.
    static let overlays = Track([(0, 0, .ease), (47, 0, .ease), (51, 1, .ease), (62, 1, .ease),
                                 (64, 0, .ease), (100, 0, .ease)])
    // Pointer: fades in at (cx0, cy0), moves onto miniature 2, rests, moves back, fades out.
    static let cursorMove = Track([(0, 0, .ease), (28, 0, .ease), (34, 1, .ease), (66, 1, .ease),
                                   (74, 0, .ease), (100, 0, .ease)])
    static let cursorOpacity = Track([(0, 0, .ease), (24, 0, .ease), (28, 1, .ease), (74, 1, .ease),
                                      (80, 0, .ease), (100, 0, .ease)])
    // Hover bar: track fades in, fill runs top to bottom, then gone.
    static let barOpacity = Track([(0, 0, .ease), (33, 0, .ease), (34, 1, .ease), (40, 1, .ease),
                                   (41, 0, .ease), (100, 0, .ease)])
    static let barFill = Track([(0, 0, .linear), (34, 0, .linear), (40, 1, .linear), (100, 1, .linear)])
    // Full popups: opacity 0 → 1 and scale 0.94 → 1 from the top right corner.
    static let full1 = Track([(0, 0, .ease), (5, 0, .ease), (12, 1, .ease), (84, 1, .ease),
                              (92, 0, .ease), (100, 0, .ease)])
    static let full2 = Track([(0, 0, .ease), (28, 0, .ease), (35, 1, .ease), (84, 1, .ease),
                              (92, 0, .ease), (100, 0, .ease)])
}

// MARK: - Drawing

private func rgb(_ hex: UInt32, _ alpha: Double = 1) -> Color {
    Color(
        .sRGB,
        red: Double((hex >> 16) & 0xFF) / 255,
        green: Double((hex >> 8) & 0xFF) / 255,
        blue: Double(hex & 0xFF) / 255,
        opacity: alpha
    )
}

/// Mock variables of proposal A (`--r`, `--mw` …) and the drawing of every part.
/// The geometry is that of the mock (popups on the right); `mirrored` reflects the positions of
/// popups, pointer and hover bar for the left edge. Desktop and the drawn shapes stay as they are.
private struct SceneGeometry {
    let size: CGSize
    var mirrored = false

    // Variables in % of the tile (widths of the width, heights and tops of the height).
    static let r = 3.0, mw = 17.0, mh = 15.3, ew = 42.0, eh = 37.8
    static let t1 = 11.0, t2 = 29.0, t3 = 47.0
    static let fw = 42.0, fh = 37.8, f2t = 51.8
    static let cx0 = 52.0, cy0 = 74.0

    static let dockColors: [UInt32] = [0x4F8DF7, 0xF2B63C, 0xE9586A, 0x52C26B, 0xF5D54A,
                                       0xF4F4F6, 0x76C6F2, 0x8A7CF0, 0x5B5F6B, 0xA9ACB4]

    var w: CGFloat { size.width }
    var h: CGFloat { size.height }
    /// 1 cqw: 1 % of the tile width.
    var cq: CGFloat { size.width / 100 }
    func x(_ percent: Double) -> CGFloat { w * percent / 100 }
    func y(_ percent: Double) -> CGFloat { h * percent / 100 }

    /// Right edge of the popups (`right: var(--r)`).
    var popupRight: CGFloat { w - x(Self.r) }

    /// Mock frame → frame on the chosen side.
    func place(_ rect: CGRect) -> CGRect {
        guard mirrored else { return rect }
        return CGRect(x: w - rect.maxX, y: rect.minY, width: rect.width, height: rect.height)
    }

    func place(_ point: CGPoint) -> CGPoint {
        mirrored ? CGPoint(x: w - point.x, y: point.y) : point
    }

    func isVisible(_ rect: CGRect) -> Bool { rect.maxX > 0 && rect.minX < w }

    // MARK: Desktop

    func drawDesktop(in context: GraphicsContext) {
        let bounds = CGRect(origin: .zero, size: size)
        // linear-gradient(170deg, #3553B0, #2C4598 55%, #3B5BB8)
        let angle = 170.0 * .pi / 180
        let direction = CGVector(dx: sin(angle), dy: -cos(angle))
        let length = abs(w * direction.dx) + abs(h * direction.dy)
        let center = CGPoint(x: w / 2, y: h / 2)
        let startPoint = CGPoint(x: center.x - direction.dx * length / 2, y: center.y - direction.dy * length / 2)
        let endPoint = CGPoint(x: center.x + direction.dx * length / 2, y: center.y + direction.dy * length / 2)
        context.fill(Path(bounds), with: .linearGradient(
            Gradient(stops: [
                .init(color: rgb(0x3553B0), location: 0),
                .init(color: rgb(0x2C4598), location: 0.55),
                .init(color: rgb(0x3B5BB8), location: 1),
            ]),
            startPoint: startPoint, endPoint: endPoint
        ))
        drawMenuBar(in: context)
        drawBackgroundWindow(in: context)
        drawDock(in: context)
    }

    /// Menu bar 6.5 % high, pills 1.5 cqw high, gap 1.3 cqw, padding 0 2 cqw.
    private func drawMenuBar(in context: GraphicsContext) {
        let barHeight = y(6.5)
        context.fill(Path(CGRect(x: 0, y: 0, width: w, height: barHeight)), with: .color(rgb(0x141E50, 0.35)))
        let pillHeight = 1.5 * cq
        let top = (barHeight - pillHeight) / 2
        let pill = rgb(0x9DB4F5)
        var left = 2 * cq
        for width in [1.6, 4, 6, 4] {
            let rect = CGRect(x: left, y: top, width: width * cq, height: pillHeight)
            context.fill(Path(roundedRect: rect, cornerRadius: pillHeight / 2), with: .color(pill))
            left += (width + 1.3) * cq
        }
        var right = w - 2 * cq
        for width in [5, 1.6, 1.6] {
            let rect = CGRect(x: right - width * cq, y: top, width: width * cq, height: pillHeight)
            context.fill(Path(roundedRect: rect, cornerRadius: pillHeight / 2), with: .color(pill))
            right -= (width + 1.3) * cq
        }
    }

    /// Background window (left 12 %, top 15 %, 50 × 62 %) with title bar, text lines and three tiles.
    private func drawBackgroundWindow(in context: GraphicsContext) {
        let frame = CGRect(x: x(12), y: y(15), width: x(50), height: y(62))
        let shape = Path(roundedRect: frame, cornerRadius: 1.4 * cq)
        var window = context
        window.clip(to: shape)
        window.fill(shape, with: .color(rgb(0x263A7C)))
        window.fill(Path(CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height * 0.14)),
                    with: .color(rgb(0x1F3170)))
        let lines: [(top: Double, left: Double, width: Double, opacity: Double)] = [
            (24, 14, 44, 1), (31, 14, 36, 0.8), (42, 14, 30, 0.55), (42, 52, 30, 0.55),
        ]
        for line in lines {
            let rect = CGRect(x: frame.minX + frame.width * line.left / 100,
                              y: frame.minY + frame.height * line.top / 100,
                              width: frame.width * line.width / 100,
                              height: frame.height * 0.022)
            window.fill(Path(roundedRect: rect, cornerRadius: min(cq, rect.height / 2)),
                        with: .color(rgb(0xAFC2F7, line.opacity)))
        }
        for (index, left) in [14.0, 40, 66].enumerated() {
            let tile = CGRect(x: frame.minX + frame.width * left / 100, y: frame.minY + frame.height * 0.55,
                              width: frame.width * 0.21, height: frame.height * 0.30)
            window.fill(Path(roundedRect: tile, cornerRadius: cq), with: .color(rgb(0x1C2A5E)))
            let side = tile.width * 0.5
            let glyph = CGRect(x: tile.midX - side / 2, y: tile.midY - side / 2, width: side, height: side)
            switch index {
            case 0:
                window.fill(Path(ellipseIn: glyph), with: .color(rgb(0x8B7FF0)))
            case 1:
                window.fill(Path(roundedRect: glyph, cornerRadius: side * 0.2), with: .color(rgb(0x7CC8F5)))
            default:
                var triangle = Path()
                triangle.move(to: CGPoint(x: glyph.midX, y: glyph.minY + side * 0.05))
                triangle.addLine(to: CGPoint(x: glyph.maxX, y: glyph.minY + side * 0.95))
                triangle.addLine(to: CGPoint(x: glyph.minX, y: glyph.minY + side * 0.95))
                triangle.closeSubpath()
                window.fill(triangle, with: .color(rgb(0xF06A4A)))
            }
        }
    }

    /// Dock: centered, bottom 2.4 %, 9 % high, padding 0 1.2 cqw, ten 3.6 cqw squares, gap 0.9 cqw.
    private func drawDock(in context: GraphicsContext) {
        let count = CGFloat(Self.dockColors.count)
        let width = (2 * 1.2 + count * 3.6 + (count - 1) * 0.9) * cq
        let height = y(9)
        let frame = CGRect(x: (w - width) / 2, y: h - y(2.4) - height, width: width, height: height)
        context.fill(Path(roundedRect: frame, cornerRadius: min(2 * cq, height / 2)),
                     with: .color(rgb(0x283C82, 0.75)))
        let side = 3.6 * cq
        var left = frame.minX + 1.2 * cq
        for color in Self.dockColors {
            let rect = CGRect(x: left, y: frame.midY - side / 2, width: side, height: side)
            context.fill(Path(roundedRect: rect, cornerRadius: 0.9 * cq), with: .color(rgb(color)))
            left += side + 0.9 * cq
        }
    }

    // MARK: Popups

    /// Popup with its top right corner at (`popupRight` + shift, top), mirrored if needed.
    private func popupRect(top: Double, width: Double, height: Double, shiftPercent: Double = 0) -> CGRect {
        let rectWidth = x(width)
        return place(CGRect(x: popupRight - rectWidth + rectWidth * shiftPercent / 100, y: y(top),
                            width: rectWidth, height: y(height)))
    }

    /// Popup: camera scene silhouette (sky/ground, house, tree), overlays, shadow and 1 pt ring.
    private func drawPopup(in context: GraphicsContext, rect: CGRect, overlayOpacity: Double) {
        let radius = 1.2 * cq
        let shape = Path(roundedRect: rect, cornerRadius: radius)
        // box-shadow: 0 0 0 1px rgba(255,255,255,.12), 0 .8cqw 2cqw rgba(0,0,0,.4)
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.4), radius: cq, x: 0, y: 0.8 * cq))
            layer.fill(shape, with: .color(rgb(0x343B47)))
        }
        context.stroke(Path(roundedRect: rect.insetBy(dx: -0.5, dy: -0.5), cornerRadius: radius + 0.5),
                       with: .color(.white.opacity(0.12)), lineWidth: 1)

        var inner = context
        inner.clip(to: shape)
        let silhouette = rgb(0x1F242D)
        inner.fill(Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.56)),
                   with: .color(rgb(0x56657A)))
        inner.fill(Path(CGRect(x: rect.minX, y: rect.minY + rect.height * 0.56,
                               width: rect.width, height: rect.height * 0.44)),
                   with: .color(rgb(0x343B47)))
        // House: left 15 %, bottom 44 %, 36 × 30 %, gable polygon(0 40%, 50% 0, 100% 40%, 100% 100%, 0 100%).
        let house = CGRect(x: rect.minX + rect.width * 0.15, y: rect.maxY - rect.height * 0.44 - rect.height * 0.30,
                           width: rect.width * 0.36, height: rect.height * 0.30)
        var housePath = Path()
        housePath.move(to: CGPoint(x: house.minX, y: house.minY + house.height * 0.4))
        housePath.addLine(to: CGPoint(x: house.midX, y: house.minY))
        housePath.addLine(to: CGPoint(x: house.maxX, y: house.minY + house.height * 0.4))
        housePath.addLine(to: CGPoint(x: house.maxX, y: house.maxY))
        housePath.addLine(to: CGPoint(x: house.minX, y: house.maxY))
        housePath.closeSubpath()
        inner.fill(housePath, with: .color(silhouette))
        // Tree: right 16 %, bottom 43 %, 15 × 34 %, border-radius 50% 50% 10% 10%.
        let tree = CGRect(x: rect.maxX - rect.width * 0.16 - rect.width * 0.15,
                          y: rect.maxY - rect.height * 0.43 - rect.height * 0.34,
                          width: rect.width * 0.15, height: rect.height * 0.34)
        inner.fill(Self.ellipticRoundedRect(tree, top: 0.5, bottom: 0.1), with: .color(silhouette))

        guard overlayOpacity > 0 else { return }
        var overlay = inner
        overlay.opacity = overlayOpacity
        drawOverlays(in: overlay, rect: rect)
    }

    /// Overlays: chip top center, three buttons top right, bar bottom center (all black 60 %).
    private func drawOverlays(in context: GraphicsContext, rect: CGRect) {
        let fill = GraphicsContext.Shading.color(.black.opacity(0.6))
        // Chip: top 7 %, 34 × 9 %, radius 2 cqw, green dot at 9 % / 34 %, 1 cqw.
        let chip = CGRect(x: rect.midX - rect.width * 0.17, y: rect.minY + rect.height * 0.07,
                          width: rect.width * 0.34, height: rect.height * 0.09)
        context.fill(Path(roundedRect: chip, cornerRadius: min(2 * cq, chip.height / 2)), with: fill)
        context.fill(Path(ellipseIn: CGRect(x: chip.minX + chip.width * 0.09, y: chip.minY + chip.height * 0.34,
                                            width: cq, height: cq)),
                     with: .color(rgb(0x34C759)))
        // Top right: top 6 %, right 4 %, three 2.6 cqw circles, gap 1 cqw.
        let small = 2.6 * cq
        var right = rect.maxX - rect.width * 0.04
        for _ in 0..<3 {
            context.fill(Path(ellipseIn: CGRect(x: right - small, y: rect.minY + rect.height * 0.06,
                                                width: small, height: small)), with: fill)
            right -= small + cq
        }
        // Bottom bar: bottom 7 %, two 3.4 cqw circles and an 8 cqw pill, gap 1 cqw.
        let big = 3.4 * cq
        let total = big * 2 + 8 * cq + 2 * cq
        let top = rect.maxY - rect.height * 0.07 - big
        var left = rect.midX - total / 2
        for width in [big, big, 8 * cq] {
            let item = CGRect(x: left, y: top, width: width, height: big)
            context.fill(Path(roundedRect: item, cornerRadius: big / 2), with: fill)
            left += width + cq
        }
    }

    /// `border-radius: a a b b` in % (elliptic corners: horizontal % of the width, vertical % of the height).
    private static func ellipticRoundedRect(_ rect: CGRect, top: CGFloat, bottom: CGFloat) -> Path {
        let k: CGFloat = 0.5523
        let tx = rect.width * top, ty = rect.height * top
        let bx = rect.width * bottom, by = rect.height * bottom
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + tx, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tx, y: rect.minY))
        path.addCurve(to: CGPoint(x: rect.maxX, y: rect.minY + ty),
                      control1: CGPoint(x: rect.maxX - tx + tx * k, y: rect.minY),
                      control2: CGPoint(x: rect.maxX, y: rect.minY + ty - ty * k))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - by))
        path.addCurve(to: CGPoint(x: rect.maxX - bx, y: rect.maxY),
                      control1: CGPoint(x: rect.maxX, y: rect.maxY - by + by * k),
                      control2: CGPoint(x: rect.maxX - bx + bx * k, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + bx, y: rect.maxY))
        path.addCurve(to: CGPoint(x: rect.minX, y: rect.maxY - by),
                      control1: CGPoint(x: rect.minX + bx - bx * k, y: rect.maxY),
                      control2: CGPoint(x: rect.minX, y: rect.maxY - by + by * k))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + ty))
        path.addCurve(to: CGPoint(x: rect.minX + tx, y: rect.minY),
                      control1: CGPoint(x: rect.minX, y: rect.minY + ty - ty * k),
                      control2: CGPoint(x: rect.minX + tx - tx * k, y: rect.minY))
        path.closeSubpath()
        return path
    }

    // MARK: Layouts

    /// Miniature cycle: three slide in, the pointer rests on the second, the hover bar fills,
    /// the second grows (the third moves down), shrinks back, all slide out. No click.
    func drawMiniatures(in context: GraphicsContext, at p: Double) {
        let grow = Keys.m2Grow.value(at: p)
        let m1 = popupRect(top: Self.t1, width: Self.mw, height: Self.mh, shiftPercent: Keys.m1Shift.value(at: p))
        let m2 = popupRect(top: Self.t2,
                           width: Self.mw + (Self.ew - Self.mw) * grow,
                           height: Self.mh + (Self.eh - Self.mh) * grow,
                           shiftPercent: Keys.m2Shift.value(at: p))
        let m3 = popupRect(top: Keys.m3Top.value(at: p), width: Self.mw, height: Self.mh,
                           shiftPercent: Keys.m3Shift.value(at: p))
        // Paint order of the mock: m1, m3, hover bar, then m2 (z-index 2), pointer (z-index 3).
        if isVisible(m1) { drawPopup(in: context, rect: m1, overlayOpacity: 0) }
        if isVisible(m3) { drawPopup(in: context, rect: m3, overlayOpacity: 0) }

        // Hover bar: left = 100 % − r − mw − 1.7 %, top t2, 0.8 cqw wide, mh high, radius 0.4 cqw.
        let barOpacity = Keys.barOpacity.value(at: p)
        if barOpacity > 0 {
            let bar = place(CGRect(x: x(100 - Self.r - Self.mw - 1.7), y: y(Self.t2), width: 0.8 * cq, height: y(Self.mh)))
            var layer = context
            layer.opacity = barOpacity
            let shape = Path(roundedRect: bar, cornerRadius: 0.4 * cq)
            layer.clip(to: shape)
            layer.fill(shape, with: .color(.white.opacity(0.22)))
            let fill = bar.height * Keys.barFill.value(at: p)
            layer.fill(Path(CGRect(x: bar.minX, y: bar.minY, width: bar.width, height: fill)),
                       with: .color(rgb(0xFFD84D)))
        }

        if isVisible(m2) { drawPopup(in: context, rect: m2, overlayOpacity: Keys.overlays.value(at: p)) }

        let cursorOpacity = Keys.cursorOpacity.value(at: p)
        if cursorOpacity > 0 {
            let move = Keys.cursorMove.value(at: p)
            let rest = CGPoint(x: x(100 - Self.r - Self.mw / 2), y: y(Self.t2 + Self.mh / 2))
            let origin = place(CGPoint(x: x(Self.cx0) + (rest.x - x(Self.cx0)) * move,
                                       y: y(Self.cy0) + (rest.y - y(Self.cy0)) * move))
            var layer = context
            layer.opacity = cursorOpacity
            drawCursor(in: layer, at: origin)
        }
    }

    /// Pointer: 2.6 × 3.6 cqw box, SVG path in a 22 × 30 viewBox (fill #111, stroke white 1.8).
    private func drawCursor(in context: GraphicsContext, at origin: CGPoint) {
        let scale = min(2.6 * cq / 22, 3.6 * cq / 30)
        let offsetX = (2.6 * cq - 22 * scale) / 2
        let offsetY = (3.6 * cq - 30 * scale) / 2
        let points: [(CGFloat, CGFloat)] = [(2, 2), (2, 24), (8, 18.5), (12, 27), (15.5, 25.5), (11.6, 17.2), (19.5, 17.2)]
        var path = Path()
        for (index, point) in points.enumerated() {
            let p = CGPoint(x: origin.x + offsetX + point.0 * scale, y: origin.y + offsetY + point.1 * scale)
            if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        context.fill(path, with: .color(rgb(0x111111)))
        context.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 1.8 * scale, lineJoin: .round))
    }

    /// Full cycle: two full popups fade in (scale 0.94 → 1 from the outer top corner) and out again.
    func drawFullPopups(in context: GraphicsContext, at p: Double) {
        let popups: [(top: Double, track: Track)] = [(Self.t1, Keys.full1), (Self.f2t, Keys.full2)]
        for popup in popups {
            let amount = popup.track.value(at: p)
            guard amount > 0 else { continue }
            let rect = popupRect(top: popup.top, width: Self.fw, height: Self.fh)
            let scale = 0.94 + 0.06 * amount
            var layer = context
            layer.opacity = amount
            let anchorX = mirrored ? rect.minX : rect.maxX
            layer.translateBy(x: anchorX, y: rect.minY)
            layer.scaleBy(x: scale, y: scale)
            layer.translateBy(x: -anchorX, y: -rect.minY)
            layer.drawLayer { group in
                drawPopup(in: group, rect: rect, overlayOpacity: 1)
            }
        }
    }
}
