import CoreGraphics
import XCTest
@testable import AppCore

final class MiniatureStackTests: XCTestCase {
    /// 1440 × 900 visible frame, margin 20 → column from y 880 downwards, right edge 1420.
    private let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    /// 16:9 full size → 200 × 113 miniature.
    private let wide = CGSize(width: 560, height: 315)

    private func stack(_ ids: [String]) -> MiniatureStack<String> {
        var stack = MiniatureStack<String>(side: .trailing, visible: visible, margin: 20)
        for id in ids { _ = stack.append(id, fullSize: wide) }
        return stack
    }

    // MARK: Spalte

    func testNewPopupsLineUpBelowEachOther() {
        let s = stack(["a", "b", "c"])
        XCTAssertEqual(s.frame(of: "a"), CGRect(x: 1220, y: 767, width: 200, height: 113))
        XCTAssertEqual(s.frame(of: "b"), CGRect(x: 1220, y: 644, width: 200, height: 113))
        XCTAssertEqual(s.frame(of: "c"), CGRect(x: 1220, y: 521, width: 200, height: 113))
    }

    func testClosingPopupLeavesThenTheOthersCloseUp() {
        var s = stack(["a", "b", "c"])
        let out = s.beginLeaving("a", screenFrame: screen)
        XCTAssertEqual(out, CGRect(x: 1470, y: 767, width: 200, height: 113), "slides out beyond the outer edge")
        XCTAssertEqual(s.frame(of: "b")?.minY, 644, "the others wait for the slide-out")
        let moved = s.remove("a")
        XCTAssertEqual(moved["b"]?.minY, 767)
        XCTAssertEqual(moved["c"]?.minY, 644)
    }

    // MARK: Stapel steht still während des Hoverns

    func testArmedStackKeepsFramesWhenPopupAboveCloses() {
        var s = stack(["a", "b", "c"])
        let before = (s.frame(of: "b"), s.frame(of: "c"))
        XCTAssertTrue(s.arm("b"))
        XCTAssertTrue(s.isFrozen)
        _ = s.beginLeaving("a", screenFrame: screen)
        let moved = s.remove("a")
        XCTAssertTrue(moved.isEmpty, "nothing moves while a miniature is armed")
        XCTAssertEqual(s.frame(of: "b"), before.0)
        XCTAssertEqual(s.frame(of: "c"), before.1)
    }

    func testNewPopupWhileFrozenJoinsBelowTheLowest() {
        var s = stack(["a", "b"])
        s.arm("b")
        _ = s.beginLeaving("a", screenFrame: screen)
        _ = s.remove("a")
        let added = s.append("c", fullSize: wide)
        XCTAssertEqual(added["c"], CGRect(x: 1220, y: 521, width: 200, height: 113), "below b, the gap stays open")
        XCTAssertEqual(s.frame(of: "b")?.minY, 644)
    }

    func testDisarmCatchesUp() {
        var s = stack(["a", "b"])
        s.arm("b")
        _ = s.beginLeaving("a", screenFrame: screen)
        _ = s.remove("a")
        let moved = s.disarm("b")
        XCTAssertEqual(moved["b"]?.minY, 767)
        XCTAssertFalse(s.isFrozen)
    }

    // MARK: Wachsen und Nachholen

    func testGrowingKeepsTopOuterCornerAndPushesOnlyBelow() {
        var s = stack(["a", "b", "c"])
        s.arm("b")
        _ = s.beginLeaving("a", screenFrame: screen)
        _ = s.remove("a")
        let grown = s.expand("b")
        XCTAssertEqual(grown["b"], CGRect(x: 860, y: 442, width: 560, height: 315), "top right corner stays at 1420/757")
        XCTAssertEqual(grown["c"], CGRect(x: 1220, y: 319, width: 200, height: 113), "the popup below moves down")
        XCTAssertTrue(s.isFrozen, "frozen until the grow animation finished")
    }

    func testAfterGrowingTheStackCatchesUp() {
        var s = stack(["a", "b", "c"])
        s.arm("b")
        _ = s.beginLeaving("a", screenFrame: screen)
        _ = s.remove("a")
        _ = s.expand("b")
        let moved = s.finishGrowing("b")
        XCTAssertEqual(moved["b"], CGRect(x: 860, y: 565, width: 560, height: 315), "moves up into the gap")
        XCTAssertEqual(moved["c"]?.minY, 442)
        XCTAssertFalse(s.isFrozen)
    }

    func testFinishGrowingOfAnotherPopupDoesNothing() {
        var s = stack(["a", "b"])
        s.arm("a")
        _ = s.expand("a")
        XCTAssertTrue(s.finishGrowing("b").isEmpty)
        XCTAssertEqual(s.growingID, "a")
    }

    func testOnlyOnePopupIsExpanded() {
        var s = stack(["a", "b", "c"])
        s.arm("a")
        _ = s.expand("a")
        _ = s.finishGrowing("a")
        s.arm("c")
        _ = s.expand("c")
        XCTAssertEqual(s.phase(of: "a"), .mini)
        XCTAssertEqual(s.phase(of: "c"), .expanded)
        XCTAssertEqual(s.items.filter { $0.phase == .expanded }.count, 1)
        _ = s.finishGrowing("c")
        XCTAssertEqual(s.frame(of: "a")?.size, CGSize(width: 200, height: 113))
    }

    func testCollapseReturnsToMiniature() {
        var s = stack(["a", "b"])
        s.arm("a")
        _ = s.expand("a")
        _ = s.finishGrowing("a")
        let moved = s.collapse("a")
        XCTAssertEqual(moved["a"], CGRect(x: 1220, y: 767, width: 200, height: 113))
        XCTAssertEqual(moved["b"]?.minY, 644)
    }

    func testArmOnlyFromMini() {
        var s = stack(["a"])
        XCTAssertTrue(s.arm("a"))
        XCTAssertFalse(s.arm("a"))
        _ = s.beginLeaving("a", screenFrame: screen)
        XCTAssertFalse(s.arm("a"), "a leaving popup cannot be hovered")
    }

    func testLeftSideSlidesOutToTheLeft() {
        var s = MiniatureStack<String>(side: .leading, visible: visible, margin: 20)
        _ = s.append("a", fullSize: wide)
        XCTAssertEqual(s.frame(of: "a")?.minX, 20)
        XCTAssertEqual(s.beginLeaving("a", screenFrame: screen)?.minX, -230)
    }

    // MARK: Schonfrist

    func testUserExitCollapsesAtOnce() {
        var guardState = MiniatureHoverGuard()
        XCTAssertEqual(guardState.pointerExited(now: Date(), isHeld: false), .collapse)
    }

    func testExitWhileHeldWaitsForRelease() {
        var guardState = MiniatureHoverGuard()
        let now = Date()
        XCTAssertEqual(guardState.pointerExited(now: now, isHeld: true), .keep)
        XCTAssertFalse(guardState.shouldCollapse(now: now, pointerInside: false, isHeld: true))
        XCTAssertTrue(guardState.shouldCollapse(now: now, pointerInside: false, isHeld: false))
    }

    func testLayoutMoveStartsGraceAndExpiresAfterTwoSeconds() {
        var guardState = MiniatureHoverGuard()
        let now = Date()
        guardState.noteLayoutMove(now: now, duration: 0.3)
        XCTAssertEqual(guardState.pointerExited(now: now.addingTimeInterval(0.2), isHeld: false), .startGrace)
        XCTAssertTrue(guardState.isGraceRunning)
        XCTAssertFalse(guardState.shouldCollapse(now: now.addingTimeInterval(1.5), pointerInside: false, isHeld: false))
        XCTAssertTrue(guardState.shouldCollapse(now: now.addingTimeInterval(2.3), pointerInside: false, isHeld: false))
    }

    func testFrameSettledOutsideStartsGrace() {
        var guardState = MiniatureHoverGuard()
        let now = Date()
        XCTAssertEqual(guardState.frameSettled(pointerInside: false, now: now), .startGrace)
        XCTAssertEqual(guardState.graceDeadline, now.addingTimeInterval(2))
    }

    func testPointerBackCancelsGrace() {
        var guardState = MiniatureHoverGuard()
        let now = Date()
        _ = guardState.frameSettled(pointerInside: false, now: now)
        XCTAssertFalse(guardState.shouldCollapse(now: now.addingTimeInterval(1), pointerInside: true, isHeld: false))
        XCTAssertFalse(guardState.isGraceRunning)
        XCTAssertFalse(guardState.shouldCollapse(now: now.addingTimeInterval(3), pointerInside: true, isHeld: false))
    }

    func testExitAfterLayoutMoveIsTheUsers() {
        var guardState = MiniatureHoverGuard()
        let now = Date()
        guardState.noteLayoutMove(now: now, duration: 0.3)
        XCTAssertEqual(guardState.pointerExited(now: now.addingTimeInterval(1), isHeld: false), .collapse)
    }

    // MARK: Restzeit und Vorwarnung

    func testLineShrinksWithRemainingTime() {
        let state = MiniatureRestIndicator.state(remaining: 10, total: 20, phase: .mini, reduceMotion: false)
        XCTAssertEqual(state, MiniatureRestIndicator(lineVisible: true, lineFraction: 0.5, lineWarning: false, nudge: 0, opacity: 1))
    }

    func testWarningInTheLastThreeSeconds() {
        let start = MiniatureRestIndicator.state(remaining: 3, total: 20, phase: .mini, reduceMotion: false)
        XCTAssertFalse(start.lineWarning)
        XCTAssertEqual(start.nudge, 0)

        let half = MiniatureRestIndicator.state(remaining: 1.5, total: 20, phase: .mini, reduceMotion: false)
        XCTAssertTrue(half.lineWarning)
        XCTAssertEqual(half.nudge, 18, accuracy: 0.001)
        XCTAssertEqual(half.opacity, 0.85, accuracy: 0.001)

        let end = MiniatureRestIndicator.state(remaining: 0, total: 20, phase: .mini, reduceMotion: false)
        XCTAssertEqual(end.nudge, 36, accuracy: 0.001)
        XCTAssertEqual(end.opacity, 0.7, accuracy: 0.001)
        XCTAssertEqual(end.lineFraction, 0)
    }

    func testReduceMotionWarnsOnlyByOpacity() {
        let state = MiniatureRestIndicator.state(remaining: 0, total: 20, phase: .mini, reduceMotion: true)
        XCTAssertEqual(state.nudge, 0)
        XCTAssertEqual(state.opacity, 0.7, accuracy: 0.001)
        XCTAssertTrue(state.lineWarning)
    }

    func testHoverJumpsBack() {
        let state = MiniatureRestIndicator.state(remaining: 1, total: 20, phase: .armed, reduceMotion: false)
        XCTAssertEqual(state, MiniatureRestIndicator(lineVisible: true, lineFraction: 0.05, lineWarning: false, nudge: 0, opacity: 1))
    }

    func testNoLineWhenExpandedLeavingOrNeverClosing() {
        XCTAssertFalse(MiniatureRestIndicator.state(remaining: 1, total: 20, phase: .expanded, reduceMotion: false).lineVisible)
        XCTAssertFalse(MiniatureRestIndicator.state(remaining: 1, total: 20, phase: .leaving, reduceMotion: false).lineVisible)
        XCTAssertEqual(MiniatureRestIndicator.state(remaining: 0, total: 0, phase: .mini, reduceMotion: false), .neutral)
    }

    func testNudgeMovesTowardsOuterEdge() {
        let frame = CGRect(x: 100, y: 0, width: 200, height: 113)
        XCTAssertEqual(frame.nudged(36, towards: .trailing).minX, 136)
        XCTAssertEqual(frame.nudged(36, towards: .leading).minX, 64)
    }

    // MARK: Pause bei Hover

    func testClockPausesAndResumesWhereItStopped() {
        let start = Date()
        var clock = AutoCloseClock(total: 20, now: start)
        XCTAssertEqual(clock.remaining(at: start.addingTimeInterval(5)), 15, accuracy: 0.001)
        clock.setPaused(true, at: start.addingTimeInterval(5))
        XCTAssertEqual(clock.remaining(at: start.addingTimeInterval(60)), 15, accuracy: 0.001, "paused while hovered")
        clock.setPaused(false, at: start.addingTimeInterval(60))
        XCTAssertEqual(clock.remaining(at: start.addingTimeInterval(65)), 10, accuracy: 0.001)
        XCTAssertEqual(clock.fraction(at: start.addingTimeInterval(65)), 0.5, accuracy: 0.001)
    }

    func testClockRestartKeepsPauseState() {
        let start = Date()
        var clock = AutoCloseClock(total: 20, now: start)
        clock.setPaused(true, at: start.addingTimeInterval(18))
        clock.restart(total: 20, at: start.addingTimeInterval(19))
        XCTAssertTrue(clock.isPaused)
        XCTAssertEqual(clock.remaining(at: start.addingTimeInterval(30)), 20, accuracy: 0.001)
    }

    func testClockPostponeKeepsTotal() {
        let start = Date()
        var clock = AutoCloseClock(total: 20, now: start)
        clock.setRemaining(5, at: start.addingTimeInterval(20))
        XCTAssertEqual(clock.total, 20)
        XCTAssertEqual(clock.remaining(at: start.addingTimeInterval(22)), 3, accuracy: 0.001)
    }

    func testDisabledClock() {
        let clock = AutoCloseClock(total: 0, now: Date())
        XCTAssertFalse(clock.isEnabled)
        XCTAssertEqual(clock.fraction(at: Date()), 0)
    }
}
