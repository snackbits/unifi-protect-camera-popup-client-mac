import CoreGraphics
import Foundation

/// State of one popup in the layout "Miniatur" (docs/design/popup-miniatur.md).
public enum MiniaturePhase: Equatable, Sendable {
    /// Small preview, the auto-close timer runs.
    case mini
    /// The pointer rests on the miniature, the 500 ms hover bar runs (stack frozen, timer paused).
    case armed
    /// Full size with overlays (timer paused). Only one popup at a time.
    case expanded
    /// Sliding out beyond the outer edge; removed afterwards.
    case leaving

    /// A click on the compact popup closes it: as a miniature and while the hover bar runs, not
    /// once it grows (`expanded`).
    public var closesOnClick: Bool { self == .mini || self == .armed }
}

/// Start of the slide-in or end of the slide-out (`PopupStackLayout.slideEnd`).
public struct MiniatureSlideEnd: Equatable, Sendable {
    public let frame: CGRect
    /// Next to a neighbouring screen: the popup stays on its own screen and fades (alpha 0 here).
    public let fades: Bool

    public init(frame: CGRect, fades: Bool) {
        self.frame = frame
        self.fades = fades
    }
}

/// Timing of the layout "Miniatur" (spec and mock `popup-miniatur-demo.html`).
public enum MiniatureTiming {
    /// Slide-in, slide-out, closing the gap, growing and shrinking.
    public static let move: TimeInterval = 0.3
    /// How long the pointer rests on a miniature before it grows.
    public static let hover: TimeInterval = 0.5
    /// Fade of the hover bar's track.
    public static let hoverBarFade: TimeInterval = 0.05
    /// Overlays fade in after growing.
    public static let overlayFadeIn: TimeInterval = 0.18
    /// An expanded popup that slid away under the pointer stays this long.
    public static let grace: TimeInterval = 2
}

/// The miniature column as data: order, phase and the target frame of every popup, and the rules
/// for when the stack may move. Every mutation returns the target frames that changed (popup id →
/// frame, AppKit screen coordinates); the caller animates the windows there.
///
/// - The stack stands still while a miniature is armed and while the expanded popup is still
///   growing (`isFrozen`): frames of existing popups are kept, new popups line up below the lowest
///   one, a closing popup leaves its gap open. Growing only pushes the popups below the growing one.
/// - Once growing has finished (`finishGrowing`) or the hover ended, the column closes up again.
public struct MiniatureStack<ID: Hashable> {
    public struct Item: Equatable {
        public let id: ID
        public var fullSize: CGSize
        public var phase: MiniaturePhase
        /// Last target frame without the warning nudge; nil until placed.
        public var frame: CGRect?
    }

    public private(set) var items: [Item] = []
    /// The popup whose grow animation still runs.
    public private(set) var growingID: ID?
    public private(set) var side: PopupAnchor.Horizontal
    public private(set) var visible: CGRect
    public private(set) var margin: CGFloat
    public let miniWidth: CGFloat
    public let gap: CGFloat

    public init(
        side: PopupAnchor.Horizontal,
        visible: CGRect,
        margin: CGFloat,
        miniWidth: CGFloat = PopupStackLayout.miniatureWidth,
        gap: CGFloat = PopupStackLayout.miniatureGap
    ) {
        self.side = side
        self.visible = visible
        self.margin = margin
        self.miniWidth = miniWidth
        self.gap = gap
    }

    // MARK: Queries

    public var isFrozen: Bool { growingID != nil || items.contains { $0.phase == .armed } }
    public var expandedID: ID? { items.first { $0.phase == .expanded }?.id }
    public var armedID: ID? { items.first { $0.phase == .armed }?.id }
    public var isEmpty: Bool { items.isEmpty }
    public func contains(_ id: ID) -> Bool { index(of: id) != nil }
    public func phase(of id: ID) -> MiniaturePhase? { index(of: id).map { items[$0].phase } }
    public func frame(of id: ID) -> CGRect? { index(of: id).flatMap { items[$0].frame } }

    // MARK: Mutations

    /// A new popup joins at the bottom (slides in from beyond the outer edge).
    public mutating func append(_ id: ID, fullSize: CGSize) -> [ID: CGRect] {
        guard !contains(id) else { return [:] }
        items.append(Item(id: id, fullSize: fullSize, phase: .mini, frame: nil))
        return relayout()
    }

    /// Screen, side or margin changed. A changed side moves everything at once (no freeze).
    public mutating func update(side: PopupAnchor.Horizontal, visible: CGRect, margin: CGFloat) -> [ID: CGRect] {
        let force = side != self.side || visible != self.visible || margin != self.margin
        self.side = side
        self.visible = visible
        self.margin = margin
        return relayout(force: force)
    }

    /// A newly learned size (aspect ratio, settings) applies on the next layout.
    public mutating func setFullSize(_ size: CGSize, for id: ID) {
        guard let i = index(of: id) else { return }
        items[i].fullSize = size
    }

    /// Running moves were stopped where they are (the pointer entered a miniature): these frames
    /// replace the targets, so a frozen stack keeps them.
    public mutating func freeze(at frames: [ID: CGRect]) {
        for i in items.indices where items[i].phase != .leaving {
            if let frame = frames[items[i].id] { items[i].frame = frame }
        }
    }

    /// The pointer entered a miniature: the hover bar runs, the stack stands still. Only one is
    /// armed: another armed miniature returns to mini.
    @discardableResult
    public mutating func arm(_ id: ID) -> Bool {
        guard let i = index(of: id), items[i].phase == .mini else { return false }
        for j in items.indices where items[j].phase == .armed {
            items[j].phase = .mini
        }
        items[i].phase = .armed
        return true
    }

    /// The pointer left an armed miniature before it grew: back to mini, the stack catches up.
    public mutating func disarm(_ id: ID) -> [ID: CGRect] {
        guard let i = index(of: id), items[i].phase == .armed else { return [:] }
        items[i].phase = .mini
        return relayout()
    }

    /// The hover time is over: the popup grows from its top outer corner, the popups below move
    /// down, every other expanded popup returns to mini (only one is big).
    public mutating func expand(_ id: ID) -> [ID: CGRect] {
        guard let i = index(of: id), items[i].phase == .armed || items[i].phase == .mini else { return [:] }
        for j in items.indices where items[j].phase == .expanded {
            items[j].phase = .mini
        }
        items[i].phase = .expanded
        growingID = id
        return relayout()
    }

    /// The grow animation has finished: the column catches up (the popup may move up now).
    public mutating func finishGrowing(_ id: ID) -> [ID: CGRect] {
        guard growingID == id else { return [:] }
        growingID = nil
        return relayout()
    }

    /// The expanded popup returns to a miniature.
    public mutating func collapse(_ id: ID) -> [ID: CGRect] {
        guard let i = index(of: id), items[i].phase == .expanded else { return [:] }
        items[i].phase = .mini
        if growingID == id { growingID = nil }
        return relayout()
    }

    /// Starts the slide-out: returns its end beyond the outer edge of `screenFrame` (or at the edge,
    /// fading, next to one of `otherScreens`). The others stay where they are until `remove` (the
    /// column closes up after the slide-out).
    public mutating func beginLeaving(_ id: ID, screenFrame: CGRect, otherScreens: [CGRect] = []) -> MiniatureSlideEnd? {
        guard let i = index(of: id), items[i].phase != .leaving else { return nil }
        if growingID == id { growingID = nil }
        items[i].phase = .leaving
        let current = items[i].frame ?? PopupStackLayout.miniatureFrame(
            size: size(of: items[i]), top: miniatureArea.maxY, side: side, area: miniatureArea
        )
        let out = PopupStackLayout.slideEnd(for: current, side: side, screenFrame: screenFrame, otherScreens: otherScreens)
        items[i].frame = out.frame
        return out
    }

    /// Slide-out finished (or the window is gone): the others close up unless the stack is frozen.
    public mutating func remove(_ id: ID) -> [ID: CGRect] {
        guard let i = index(of: id) else { return [:] }
        items.remove(at: i)
        if growingID == id { growingID = nil }
        return relayout()
    }

    /// Recomputes every target frame. `force` ignores the freeze (screen change).
    public mutating func relayout(force: Bool = false) -> [ID: CGRect] {
        let targets = (isFrozen && !force) ? frozenFrames() : compactFrames()
        var changed: [ID: CGRect] = [:]
        for i in items.indices {
            guard let target = targets[items[i].id], items[i].frame != target else { continue }
            items[i].frame = target
            changed[items[i].id] = target
        }
        return changed
    }

    // MARK: Layout

    private var miniatureArea: CGRect { PopupStackLayout.miniatureArea(visible: visible, margin: margin) }

    private func size(of item: Item) -> CGSize {
        PopupStackLayout.miniatureSize(
            full: item.fullSize, expanded: item.phase == .expanded, area: miniatureArea, miniWidth: miniWidth
        )
    }

    /// Normal column: no gaps, the expanded popup at its full size.
    private func compactFrames() -> [ID: CGRect] {
        let live = items.filter { $0.phase != .leaving }
        let frames = PopupStackLayout.miniatureFrames(
            fullSizes: live.map(\.fullSize),
            expandedIndex: live.firstIndex { $0.phase == .expanded },
            side: side,
            visible: visible,
            margin: margin,
            miniWidth: miniWidth,
            gap: gap
        )
        return Dictionary(uniqueKeysWithValues: zip(live.map(\.id), frames))
    }

    /// Frozen column: placed popups keep their top (a size change keeps the top outer corner),
    /// the growing popup pushes only the popups below it, new popups line up under the lowest one.
    private func frozenFrames() -> [ID: CGRect] {
        let area = miniatureArea
        var result: [ID: CGRect] = [:]
        var nextTop = area.maxY
        var cursor: CGFloat?
        for item in items where item.phase != .leaving {
            let size = size(of: item)
            let top: CGFloat
            if item.id == growingID {
                top = item.frame?.maxY ?? nextTop
            } else if let cursor {
                top = cursor
            } else if let frame = item.frame {
                top = frame.maxY
            } else {
                top = nextTop
            }
            let frame = PopupStackLayout.miniatureFrame(size: size, top: top, side: side, area: area)
            result[item.id] = frame
            if item.id == growingID || cursor != nil {
                cursor = frame.minY - gap
            }
            nextTop = min(nextTop, frame.minY - gap)
        }
        return result
    }

    private func index(of id: ID) -> Int? { items.firstIndex { $0.id == id } }
}

/// When the expanded popup returns to a miniature after the pointer is no longer on it.
/// - The user moved the pointer out: at once (unless a menu is open or it talks: then as soon as
///   that ends).
/// - The popup slid away under the pointer because the column closed up: a grace period of 2 s;
///   the pointer coming back keeps it big.
public struct MiniatureHoverGuard: Equatable {
    public enum Action: Equatable {
        case collapse
        case startGrace
        case keep
    }

    /// End of the running grace period.
    public private(set) var graceDeadline: Date?
    /// The expanded popup is moved by the column until then (its exits are not the user's).
    public private(set) var layoutMoveUntil: Date?
    /// The pointer left while a menu was open or it talked: shrink when that ends.
    public private(set) var collapseWhenReleased = false

    public init() {}

    public var isGraceRunning: Bool { graceDeadline != nil }

    /// The column moves the expanded popup (`duration` = animation length).
    public mutating func noteLayoutMove(now: Date, duration: TimeInterval) {
        let until = now.addingTimeInterval(duration + 0.1)
        layoutMoveUntil = max(layoutMoveUntil ?? until, until)
    }

    /// The tracking area reported that the pointer left the expanded popup.
    public mutating func pointerExited(now: Date, isHeld: Bool) -> Action {
        if let until = layoutMoveUntil, now < until {
            return startGrace(now: now)
        }
        if isHeld {
            collapseWhenReleased = true
            return .keep
        }
        return .collapse
    }

    /// The pointer is on the expanded popup (again): no grace, no pending shrink.
    public mutating func pointerEntered() {
        graceDeadline = nil
        collapseWhenReleased = false
    }

    /// The expanded popup's frame has settled after the column moved it: the pointer may no longer
    /// be on it although the user did not move (no exit event comes then).
    public mutating func frameSettled(pointerInside: Bool, now: Date) -> Action {
        if pointerInside {
            pointerEntered()
            return .keep
        }
        guard graceDeadline == nil, !collapseWhenReleased else { return .keep }
        return startGrace(now: now)
    }

    /// Periodic check (pointer position by geometry). true = shrink now.
    public mutating func shouldCollapse(now: Date, pointerInside: Bool, isHeld: Bool) -> Bool {
        if pointerInside {
            pointerEntered()
            return false
        }
        if let deadline = graceDeadline, now >= deadline {
            graceDeadline = nil
            if isHeld {
                collapseWhenReleased = true
                return false
            }
            return true
        }
        return collapseWhenReleased && !isHeld
    }

    private mutating func startGrace(now: Date) -> Action {
        if graceDeadline == nil {
            graceDeadline = now.addingTimeInterval(MiniatureTiming.grace)
        }
        return .startGrace
    }
}

/// Auto-close countdown that can pause (hover, expanded) and resume where it stopped.
public struct AutoCloseClock: Equatable {
    /// Full running time; 0 = never closes.
    public private(set) var total: TimeInterval
    private var deadline: Date?
    private var pausedRemaining: TimeInterval?

    public init(total: TimeInterval, now: Date, paused: Bool = false) {
        self.total = max(total, 0)
        if paused {
            pausedRemaining = self.total
        } else {
            deadline = now.addingTimeInterval(self.total)
        }
    }

    public var isPaused: Bool { pausedRemaining != nil }
    public var isEnabled: Bool { total > 0 }

    public func remaining(at now: Date) -> TimeInterval {
        if let pausedRemaining { return pausedRemaining }
        guard let deadline else { return 0 }
        return max(0, deadline.timeIntervalSince(now))
    }

    /// Remaining share 1 → 0 (0 when it never closes).
    public func fraction(at now: Date) -> Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, remaining(at: now) / total))
    }

    public mutating func setPaused(_ paused: Bool, at now: Date) {
        if paused, pausedRemaining == nil {
            pausedRemaining = remaining(at: now)
            deadline = nil
        } else if !paused, let rest = pausedRemaining {
            pausedRemaining = nil
            deadline = now.addingTimeInterval(rest)
        }
    }

    /// Restarts with a new running time (a camera triggering again), keeping the pause state.
    public mutating func restart(total: TimeInterval, at now: Date) {
        let paused = isPaused
        self = AutoCloseClock(total: total, now: now, paused: paused)
    }

    /// Sets the remaining time without changing `total` (auto-close postponed while busy).
    public mutating func setRemaining(_ seconds: TimeInterval, at now: Date) {
        if isPaused {
            pausedRemaining = max(0, seconds)
        } else {
            deadline = now.addingTimeInterval(max(0, seconds))
        }
    }
}

/// Remaining-time display of a miniature ("Beides": line + warning nudge).
public struct MiniatureRestIndicator: Equatable {
    public static let warningTime: TimeInterval = 3
    public static let nudgeDistance: CGFloat = 36
    public static let warningOpacity: CGFloat = 0.7

    /// Line under the miniature (only mini/armed with a running timeout).
    public var lineVisible: Bool
    /// Line width / miniature width.
    public var lineFraction: Double
    /// Line in `#FFD84D` instead of white 75 %.
    public var lineWarning: Bool
    /// Shift towards the outer edge in points.
    public var nudge: CGFloat
    public var opacity: CGFloat

    public static let neutral = MiniatureRestIndicator(lineVisible: false, lineFraction: 1, lineWarning: false, nudge: 0, opacity: 1)

    /// While hovered (armed) or expanded the timer pauses and the display jumps back: no nudge,
    /// full opacity, white line. "Bewegung reduzieren": the warning only fades.
    public static func state(
        remaining: TimeInterval,
        total: TimeInterval,
        phase: MiniaturePhase,
        reduceMotion: Bool
    ) -> MiniatureRestIndicator {
        guard total > 0, phase == .mini || phase == .armed else { return neutral }
        let remaining = max(0, remaining)
        let fraction = min(1, remaining / total)
        guard phase == .mini, remaining < warningTime else {
            return MiniatureRestIndicator(lineVisible: true, lineFraction: fraction, lineWarning: false, nudge: 0, opacity: 1)
        }
        let k = CGFloat(min(1, max(0, 1 - remaining / warningTime)))
        return MiniatureRestIndicator(
            lineVisible: true,
            lineFraction: fraction,
            lineWarning: true,
            nudge: reduceMotion ? 0 : nudgeDistance * k,
            opacity: 1 - (1 - warningOpacity) * k
        )
    }
}

public extension CGRect {
    /// `self` moved `distance` points towards the outer edge of `side`.
    func nudged(_ distance: CGFloat, towards side: PopupAnchor.Horizontal) -> CGRect {
        guard distance != 0 else { return self }
        switch side {
        case .leading: return offsetBy(dx: -distance, dy: 0)
        case .trailing, .center: return offsetBy(dx: distance, dy: 0)
        }
    }
}
