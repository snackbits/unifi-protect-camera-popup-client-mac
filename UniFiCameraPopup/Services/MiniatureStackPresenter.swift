import AppCore
import AppKit

/// Layout "Miniatur" (docs/design/popup-miniatur.md): slides miniatures in and out, grows the
/// hovered one, keeps the column still while hovering, the 2 s grace period and the hover bar /
/// remaining-time indicators. The rules live in AppCore (`MiniatureStack`, `MiniatureHoverGuard`,
/// `MiniatureRestIndicator`); this class applies them to the windows.
@MainActor
final class MiniatureStackPresenter {
    struct Environment {
        let side: PopupAnchor.Horizontal
        let visible: CGRect
        let screenFrame: CGRect
        /// Frames of the other screens: a slide never shows on a neighbouring one.
        let otherScreens: [CGRect]
        let margin: CGFloat
        /// Current full size of a popup (settings or learned aspect ratio may have changed).
        let fullSize: (UUID) -> CGSize?
    }

    private struct Entry {
        let window: PopupWindow
        let indicator: PopupIndicatorPanel
        var animationToken = 0
        var isAnimating = false
        /// The running move is the slide-in from the edge (not stopped by a hover elsewhere).
        var isSlidingIn = false
        /// Window frame when the hover began, before the warning nudge jumped back (the pointer
        /// still counts as on the miniature there).
        var armFrame: NSRect?
    }

    /// Curves of the mock: slide-in ease-out, slide-out ease-in, everything else ease-in-out.
    private static let slideIn = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.25, 1)
    private static let slideOut = CAMediaTimingFunction(controlPoints: 0.55, 0, 0.8, 0.3)
    private static let move = CAMediaTimingFunction(name: .easeInEaseOut)

    private let environment: () -> Environment
    private var stack: MiniatureStack<UUID>
    private var entries: [UUID: Entry] = [:]
    private var hoverGuard = MiniatureHoverGuard()
    /// The running hover bar's timer and the miniature it belongs to.
    private var armTimer: (id: UUID, timer: Timer)?
    private var tickTimer: Timer?

    init(environment: @escaping () -> Environment) {
        self.environment = environment
        stack = MiniatureStack(side: .trailing, visible: .zero, margin: 0)
    }

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    func contains(_ id: UUID) -> Bool { entries[id] != nil }
    func isLeaving(_ id: UUID) -> Bool { stack.phase(of: id) == .leaving }

    // MARK: Opening and closing

    /// A new miniature slides in from beyond the outer edge (300 ms ease-out) at the bottom of the column.
    func add(id: UUID, window: PopupWindow, fullSize: CGSize) {
        let env = environment()
        syncEnvironment(env, instant: true)

        let indicator = PopupIndicatorPanel(side: env.side)
        entries[id] = Entry(window: window, indicator: indicator)
        window.zoomReferenceWidth = fullSize.width
        window.onHoverChange = { [weak self] inside in self?.hoverChanged(id, inside: inside) }
        window.compactClickCloses = { [weak self] in self?.stack.phase(of: id)?.closesOnClick ?? true }
        window.closeInterceptor = { [weak self, weak window] in
            guard let self else {
                window?.finishClose()
                return
            }
            self.beginLeave(id)
        }

        var frames = stack.append(id, fullSize: fullSize)
        guard let base = frames.removeValue(forKey: id) ?? stack.frame(of: id) else { return }
        let start = PopupStackLayout.slideEnd(
            for: base, side: env.side, screenFrame: env.screenFrame, otherScreens: env.otherScreens
        )
        let fades = start.fades && !reduceMotion
        window.setFrame(reduceMotion ? base : start.frame, display: false)
        indicator.setFrame(PopupIndicatorPanel.frame(around: reduceMotion ? base : start.frame), display: false)
        if fades {
            window.alphaValue = 0
            indicator.alphaValue = 0
        }
        // Show without stealing focus so the user can keep typing in other apps.
        window.orderFrontRegardless()
        indicator.orderFrontRegardless()
        animate(id, to: base, windowFrame: base, curve: Self.slideIn, alongside: fades ? {
            window.animator().alphaValue = 1
            indicator.animator().alphaValue = 1
        } : nil)
        apply(frames)
        startTicking()
        tick()
    }

    /// Closing (button, click on the miniature, auto-close, replaced): slide out (300 ms ease-in),
    /// then the window closes and the others close up (`remove`).
    private func beginLeave(_ id: UUID) {
        guard let entry = entries[id] else { return }
        cancelArmTimer(of: id)
        if stack.expandedID == id { hoverGuard = MiniatureHoverGuard() }
        entry.indicator.stopHoverBar(animated: false)
        entry.indicator.showRest(.neutral)
        let env = environment()
        guard let out = stack.beginLeaving(id, screenFrame: env.screenFrame, otherScreens: env.otherScreens),
              !reduceMotion else {
            entry.window.finishClose()
            return
        }
        animate(id, to: out.frame, windowFrame: out.frame, curve: Self.slideOut, alongside: {
            // The warning faded it; the slide-out itself is the normal one (next to a neighbouring
            // screen it fades out at the edge).
            entry.window.animator().alphaValue = out.fades ? 0 : 1
        }, completion: { [weak window = entry.window] _ in
            window?.finishClose()
        })
    }

    /// The window is closed (after the slide-out or directly): drop it, the others close up.
    func remove(_ id: UUID) {
        guard let entry = entries.removeValue(forKey: id) else { return }
        entry.window.onHoverChange = nil
        entry.window.compactClickCloses = nil
        entry.window.closeInterceptor = nil
        entry.indicator.orderOut(nil)
        entry.indicator.close()
        cancelArmTimer(of: id)
        if stack.expandedID == id { hoverGuard = MiniatureHoverGuard() }
        apply(stack.remove(id))
        if entries.isEmpty { stopTicking() }
    }

    /// Screen, side, margin or sizes changed. A frozen column waits, except for a new screen or side.
    func relayout() {
        guard !entries.isEmpty else { return }
        let env = environment()
        for id in entries.keys {
            if let size = env.fullSize(id) { stack.setFullSize(size, for: id) }
        }
        syncEnvironment(env)
    }

    /// Takes over side, screen and margin. A new side moves every popup and its indicators there
    /// at once (no slide across the screen).
    private func syncEnvironment(_ env: Environment, instant: Bool = false) {
        let sideChanged = env.side != stack.side
        if sideChanged {
            for entry in entries.values { entry.indicator.side = env.side }
        }
        apply(stack.update(side: env.side, visible: env.visible, margin: env.margin), instant: instant || sideChanged)
    }

    // MARK: Hover

    private func hoverChanged(_ id: UUID, inside: Bool) {
        guard let phase = stack.phase(of: id), let entry = entries[id] else { return }
        if inside {
            switch phase {
            case .mini: beginHover(id)
            case .expanded: hoverGuard.pointerEntered()
            case .armed, .leaving: break
            }
            return
        }
        let mouse = NSEvent.mouseLocation
        switch phase {
        case .armed:
            // The nudge jumping back may move the window away from under a resting pointer.
            if entry.window.frame.contains(mouse) || entry.armFrame?.contains(mouse) == true { return }
            endHover(id)
        case .expanded:
            if entry.window.frame.contains(mouse) { return }
            if hoverGuard.pointerExited(now: Date(), isHeld: entry.window.isHeldOpen) == .collapse {
                collapse(id)
            }
        case .mini, .leaving:
            break
        }
    }

    /// The pointer rests on a miniature: timer paused, hover bar runs, the column stands still –
    /// running moves stop where they are, so the miniature cannot slide away under the pointer.
    private func beginHover(_ id: UUID) {
        guard entries[id] != nil, stack.phase(of: id) == .mini else { return }
        // Only one hover bar: a miniature still armed returns to mini first.
        if let armed = stack.armedID, armed != id { endHover(armed) }
        let stoppedMoves = freezeMoves()
        // Stopped elsewhere than under the pointer: not armed, the column moves on.
        guard var entry = entries[id],
              !stoppedMoves || entry.window.frame.insetBy(dx: -1, dy: -1).contains(NSEvent.mouseLocation),
              stack.arm(id) else {
            apply(stack.relayout())
            return
        }
        entry.armFrame = entry.window.frame
        entries[id] = entry
        entry.window.setAutoClosePaused(true)
        entry.indicator.startHoverBar()
        cancelArmTimer()
        let timer = Timer(timeInterval: MiniatureTiming.hover, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.expand(id) }
        }
        RunLoop.main.add(timer, forMode: .common)
        armTimer = (id, timer)
        // A popup stopped mid-resize takes its size at its stopped top; the others stand still.
        apply(stack.relayout())
        // Remaining-time display jumps back (no nudge, full opacity, white line).
        tick()
    }

    /// Stops every running move of the column where it is right now and makes the stopped frames
    /// the stack's own (`freeze(at:)`). Growing, sliding-in and sliding-out popups go on. true =
    /// something stopped.
    @discardableResult
    private func freezeMoves() -> Bool {
        var stopped: [UUID: CGRect] = [:]
        for (id, entry) in entries where entry.isAnimating && !entry.isSlidingIn {
            guard let phase = stack.phase(of: id), phase != .leaving, stack.growingID != id else { continue }
            // The indicator panel moves with the frame without the warning nudge.
            let inset = PopupIndicatorPanel.inset
            stopped[id] = entry.indicator.frame.insetBy(dx: inset, dy: inset)
            stopMove(id)
        }
        guard !stopped.isEmpty else { return false }
        stack.freeze(at: stopped)
        if let expanded = stack.expandedID, stopped[expanded] != nil { settle(expanded) }
        return true
    }

    /// Cancels the running animations of a popup and its indicator panel where they are now.
    private func stopMove(_ id: UUID) {
        guard var entry = entries[id] else { return }
        // The cancelled animation's completion sees an old token: `completion(false)`.
        entry.animationToken += 1
        entry.isAnimating = false
        entry.isSlidingIn = false
        entries[id] = entry
        let window = entry.window
        let indicator = entry.indicator
        let frame = window.frame
        let panel = indicator.frame
        let alpha = window.alphaValue
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            window.animator().setFrame(frame, display: true)
            window.animator().alphaValue = alpha
            indicator.animator().setFrame(panel, display: true)
            // A fade-in stopped half way: the line shows in full (`tick` sets the popup's opacity).
            indicator.animator().alphaValue = 1
        }
    }

    /// Invalidates the hover bar's timer (only that of `id`, if given).
    private func cancelArmTimer(of id: UUID? = nil) {
        guard let armTimer, id == nil || armTimer.id == id else { return }
        armTimer.timer.invalidate()
        self.armTimer = nil
    }

    /// The pointer left before the 500 ms were over: back to a miniature, the column catches up.
    private func endHover(_ id: UUID) {
        cancelArmTimer(of: id)
        guard var entry = entries[id] else { return }
        entry.armFrame = nil
        entries[id] = entry
        entry.indicator.stopHoverBar(animated: true)
        entry.window.setAutoClosePaused(false)
        apply(stack.disarm(id))
    }

    /// 500 ms on the miniature: it grows from its top outer corner (300 ms), the ones below move
    /// down. Overlays fade in afterwards; then the column catches up.
    private func expand(_ id: UUID) {
        if armTimer?.id == id { armTimer = nil }
        guard stack.phase(of: id) == .armed, var entry = entries[id] else { return }
        entry.armFrame = nil
        entries[id] = entry
        entry.indicator.stopHoverBar(animated: false)
        let previous = stack.expandedID
        hoverGuard = MiniatureHoverGuard()
        var frames = stack.expand(id)
        if let previous, previous != id, let other = entries[previous] {
            other.window.setCompact(true, animated: false)
            other.window.setAutoClosePaused(false)
        }
        let grown = frames.removeValue(forKey: id)
        apply(frames)
        guard let grown else {
            growthFinished(id)
            return
        }
        animate(id, to: grown, windowFrame: grown, curve: Self.move, completion: { [weak self] _ in
            self?.growthFinished(id)
        })
    }

    private func growthFinished(_ id: UUID) {
        guard stack.phase(of: id) == .expanded, stack.growingID == id, let entry = entries[id] else {
            apply(stack.finishGrowing(id))
            return
        }
        entry.window.setCompact(false, animated: true)
        let moved = stack.finishGrowing(id)
        apply(moved)
        if moved[id] == nil { settle(id) }
    }

    /// Back to a miniature: overlays go at once, the timer runs again.
    private func collapse(_ id: UUID) {
        guard stack.phase(of: id) == .expanded, let entry = entries[id] else { return }
        hoverGuard = MiniatureHoverGuard()
        entry.window.setCompact(true, animated: false)
        entry.window.setAutoClosePaused(false)
        apply(stack.collapse(id))
    }

    /// The expanded popup's frame has settled after the column moved it: pointer still on it?
    private func settle(_ id: UUID) {
        guard stack.expandedID == id, stack.growingID != id, let entry = entries[id] else { return }
        _ = hoverGuard.frameSettled(pointerInside: entry.window.frame.contains(NSEvent.mouseLocation), now: Date())
    }

    // MARK: Frames

    /// Moves popups to their new frames (300 ms ease-in-out, `instant` or "Bewegung reduzieren": at once).
    private func apply(_ frames: [UUID: CGRect], instant: Bool = false) {
        let now = Date()
        for (id, base) in frames {
            guard entries[id] != nil, stack.phase(of: id) != .leaving else { continue }
            let isExpanded = stack.expandedID == id
            if isExpanded { hoverGuard.noteLayoutMove(now: now, duration: MiniatureTiming.move) }
            animate(id, to: base, windowFrame: displayFrame(id, base: base), curve: Self.move, instant: instant, completion: { [weak self] finished in
                guard finished, isExpanded else { return }
                self?.settle(id)
            })
        }
    }

    /// Popup frame including the warning nudge.
    private func displayFrame(_ id: UUID, base: CGRect) -> CGRect {
        guard let entry = entries[id], let phase = stack.phase(of: id) else { return base }
        let progress = entry.window.autoCloseProgress
        let rest = MiniatureRestIndicator.state(
            remaining: progress.remaining, total: progress.total, phase: phase, reduceMotion: reduceMotion
        )
        return base.nudged(rest.nudge, towards: stack.side)
    }

    /// Popup and indicator panel move together. `completion(true)` only when no newer move replaced it.
    private func animate(
        _ id: UUID,
        to base: CGRect,
        windowFrame: CGRect,
        curve: CAMediaTimingFunction,
        instant: Bool = false,
        alongside: (() -> Void)? = nil,
        completion: ((Bool) -> Void)? = nil
    ) {
        guard var entry = entries[id] else {
            completion?(false)
            return
        }
        entry.animationToken += 1
        let token = entry.animationToken
        let window = entry.window
        let indicator = entry.indicator
        let panelFrame = PopupIndicatorPanel.frame(around: base)

        guard !instant, !reduceMotion, window.isVisible, window.frame != windowFrame else {
            // A running move would carry on to its old target.
            if entry.isAnimating { stopMove(id) }
            entry.isAnimating = false
            entry.isSlidingIn = false
            entries[id] = entry
            window.setFrame(windowFrame, display: true)
            indicator.setFrame(panelFrame, display: true)
            alongside?()
            completion?(true)
            return
        }
        entry.isAnimating = true
        entry.isSlidingIn = curve === Self.slideIn
        entries[id] = entry
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = MiniatureTiming.move
            context.timingFunction = curve
            window.animator().setFrame(windowFrame, display: true)
            indicator.animator().setFrame(panelFrame, display: true)
            alongside?()
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, var current = self.entries[id], current.animationToken == token else {
                    completion?(false)
                    return
                }
                current.isAnimating = false
                current.isSlidingIn = false
                self.entries[id] = current
                completion?(true)
            }
        })
    }

    // MARK: Ticks (remaining time, nudge, grace period)

    private func startTicking() {
        guard tickTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func stopTicking() {
        tickTimer?.invalidate()
        tickTimer = nil
        cancelArmTimer()
        hoverGuard = MiniatureHoverGuard()
    }

    private func tick() {
        let now = Date()
        let reduce = reduceMotion
        let mouse = NSEvent.mouseLocation
        for (id, entry) in entries {
            guard let phase = stack.phase(of: id), phase != .leaving, let base = stack.frame(of: id) else { continue }
            let progress = entry.window.autoCloseProgress
            let rest = MiniatureRestIndicator.state(
                remaining: progress.remaining, total: progress.total, phase: phase, reduceMotion: reduce
            )
            entry.indicator.showRest(rest)
            // Moves may fade the popup (slide next to a neighbouring screen, warning).
            guard !entry.isAnimating else { continue }
            if entry.window.alphaValue != rest.opacity { entry.window.alphaValue = rest.opacity }
            let target = base.nudged(rest.nudge, towards: stack.side)
            if entry.window.frame != target { entry.window.setFrame(target, display: true) }
            let panel = PopupIndicatorPanel.frame(around: base)
            if entry.indicator.frame != panel { entry.indicator.setFrame(panel, display: true) }
        }

        // No exit event comes when the pointer leaves while the window moves.
        if let armed = stack.armedID, let entry = entries[armed] {
            let inside = entry.window.frame.contains(mouse) || entry.armFrame?.contains(mouse) == true
            if !inside { endHover(armed) }
        }
        if let expanded = stack.expandedID, stack.growingID != expanded, let entry = entries[expanded] {
            let inside = entry.window.frame.contains(mouse)
            if hoverGuard.shouldCollapse(now: now, pointerInside: inside, isHeld: entry.window.isHeldOpen) {
                collapse(expanded)
            }
        }
    }
}
