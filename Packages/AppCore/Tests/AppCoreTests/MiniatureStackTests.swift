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
        XCTAssertEqual(s.frame(of: "b"), CGRect(x: 1220, y: 639, width: 200, height: 113))
        XCTAssertEqual(s.frame(of: "c"), CGRect(x: 1220, y: 511, width: 200, height: 113))
    }

    func testClosingPopupLeavesThenTheOthersCloseUp() {
        var s = stack(["a", "b", "c"])
        let before = s.frame(of: "a")
        XCTAssertTrue(s.beginLeaving("a"))
        XCTAssertEqual(s.frame(of: "a"), before, "the window stays, only its content slides out")
        XCTAssertEqual(s.frame(of: "b")?.minY, 639, "the others wait for the slide-out")
        let moved = s.remove("a")
        XCTAssertEqual(moved["b"]?.minY, 767)
        XCTAssertEqual(moved["c"]?.minY, 639)
    }

    // MARK: Stapel steht still während des Hoverns

    func testArmedStackKeepsFramesWhenPopupAboveCloses() {
        var s = stack(["a", "b", "c"])
        let before = (s.frame(of: "b"), s.frame(of: "c"))
        XCTAssertTrue(s.arm("b"))
        XCTAssertTrue(s.isFrozen)
        s.beginLeaving("a")
        let moved = s.remove("a")
        XCTAssertTrue(moved.isEmpty, "nothing moves while a miniature is armed")
        XCTAssertEqual(s.frame(of: "b"), before.0)
        XCTAssertEqual(s.frame(of: "c"), before.1)
    }

    func testNewPopupWhileFrozenJoinsBelowTheLowest() {
        var s = stack(["a", "b"])
        s.arm("b")
        s.beginLeaving("a")
        _ = s.remove("a")
        let added = s.append("c", fullSize: wide)
        XCTAssertEqual(added["c"], CGRect(x: 1220, y: 511, width: 200, height: 113), "below b, the gap stays open")
        XCTAssertEqual(s.frame(of: "b")?.minY, 639)
    }

    func testDisarmCatchesUp() {
        var s = stack(["a", "b"])
        s.arm("b")
        s.beginLeaving("a")
        _ = s.remove("a")
        let moved = s.disarm("b")
        XCTAssertEqual(moved["b"]?.minY, 767)
        XCTAssertFalse(s.isFrozen)
    }

    // MARK: Wachsen und Nachholen

    func testGrowingKeepsTopOuterCornerAndPushesOnlyBelow() {
        var s = stack(["a", "b", "c"])
        s.arm("b")
        s.beginLeaving("a")
        _ = s.remove("a")
        let grown = s.expand("b")
        XCTAssertEqual(grown["b"], CGRect(x: 860, y: 437, width: 560, height: 315), "top right corner stays at 1420/757")
        XCTAssertEqual(grown["c"], CGRect(x: 1220, y: 309, width: 200, height: 113), "the popup below moves down")
        XCTAssertTrue(s.isFrozen, "frozen until the grow animation finished")
    }

    func testAfterGrowingTheStackCatchesUp() {
        var s = stack(["a", "b", "c"])
        s.arm("b")
        s.beginLeaving("a")
        _ = s.remove("a")
        _ = s.expand("b")
        let moved = s.finishGrowing("b")
        XCTAssertEqual(moved["b"], CGRect(x: 860, y: 565, width: 560, height: 315), "moves up into the gap")
        XCTAssertEqual(moved["c"]?.minY, 437)
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
        XCTAssertEqual(moved["b"]?.minY, 639)
    }

    func testArmOnlyFromMini() {
        var s = stack(["a"])
        XCTAssertTrue(s.arm("a"))
        XCTAssertFalse(s.arm("a"))
        s.beginLeaving("a")
        XCTAssertFalse(s.arm("a"), "a leaving popup cannot be hovered")
    }

    func testLeftSideSitsAtTheLeftMargin() {
        var s = MiniatureStack<String>(side: .leading, visible: visible, margin: 20)
        _ = s.append("a", fullSize: wide)
        XCTAssertEqual(s.frame(of: "a"), CGRect(x: 20, y: 767, width: 200, height: 113))
    }

    /// Outer edge exactly `margin` from the visible frame's edge, top exactly `margin` below its
    /// top – also on a second screen with an offset origin and a menu bar.
    func testColumnKeepsTheEdgeMarginOnAnyScreen() {
        let second = CGRect(x: 1728, y: 37, width: 1920, height: 1050)
        var right = MiniatureStack<String>(side: .trailing, visible: second, margin: 20)
        _ = right.append("a", fullSize: wide)
        XCTAssertEqual(right.frame(of: "a")?.maxX, second.maxX - 20)
        XCTAssertEqual(right.frame(of: "a")?.maxY, second.maxY - 20)
        var left = MiniatureStack<String>(side: .leading, visible: second, margin: 20)
        _ = left.append("a", fullSize: wide)
        XCTAssertEqual(left.frame(of: "a")?.minX, second.minX + 20)
        XCTAssertEqual(left.frame(of: "a")?.maxY, second.maxY - 20)
    }

    // MARK: Einfrieren mitten in der Bewegung

    /// a was big and collapses; b slides up towards a's place. The pointer enters b mid-move:
    /// the moves stop where they are and b stays under the pointer while it is armed.
    func testFreezeKeepsStoppedFramesWhileArmed() {
        var s = stack(["a", "b", "c"])
        s.arm("a")
        _ = s.expand("a")
        _ = s.finishGrowing("a")
        let targets = s.collapse("a")
        XCTAssertEqual(targets["b"]?.minY, 639)

        let midA = CGRect(x: 1040, y: 666, width: 380, height: 214)
        let midB = CGRect(x: 1220, y: 543, width: 200, height: 113)
        let midC = CGRect(x: 1220, y: 420, width: 200, height: 113)
        s.freeze(at: ["a": midA, "b": midB, "c": midC])
        XCTAssertTrue(s.arm("b"))
        let moved = s.relayout()
        XCTAssertEqual(moved["a"], CGRect(x: 1220, y: 767, width: 200, height: 113),
                       "a shrinks to its miniature in place (top outer corner kept)")
        XCTAssertNil(moved["b"], "b does not slide away under the pointer")
        XCTAssertNil(moved["c"])
        XCTAssertEqual(s.frame(of: "b"), midB)
        XCTAssertEqual(s.frame(of: "c"), midC)

        let caughtUp = s.disarm("b")
        XCTAssertEqual(caughtUp["b"]?.minY, 639, "after the hover the column catches up")
        XCTAssertEqual(caughtUp["c"]?.minY, 511)
    }

    /// The pointer is no longer on b after stopping: b is not armed, the column moves on.
    func testFreezeWithoutArmCatchesUp() {
        var s = stack(["a", "b"])
        s.beginLeaving("a")
        let targets = s.remove("a")
        XCTAssertEqual(targets["b"]?.minY, 767)
        s.freeze(at: ["b": CGRect(x: 1220, y: 700, width: 200, height: 113)])
        XCTAssertFalse(s.isFrozen)
        XCTAssertEqual(s.relayout()["b"]?.minY, 767)
    }

    func testFreezeIgnoresLeavingPopups() {
        var s = stack(["a", "b"])
        let before = s.frame(of: "a")
        s.beginLeaving("a")
        s.freeze(at: ["a": CGRect(x: 1300, y: 767, width: 200, height: 113)])
        XCTAssertEqual(s.frame(of: "a"), before)
    }

    // MARK: Großes Popup weicht nach oben aus

    private func frames(_ sizes: [CGSize], expanded: Int) -> [CGRect] {
        PopupStackLayout.miniatureFrames(fullSizes: sizes, expandedIndex: expanded, side: .trailing, visible: visible, margin: 20)
    }

    func testExpandedThatFitsDoesNotMove() {
        let result = frames(Array(repeating: wide, count: 5), expanded: 4)
        XCTAssertEqual(result[4], CGRect(x: 860, y: 53, width: 560, height: 315), "top outer corner stays")
        XCTAssertEqual(result[3], CGRect(x: 1220, y: 383, width: 200, height: 113))
    }

    func testExpandedMovesUpAndCoveredMiniaturesLineUpBelow() {
        let big = CGSize(width: 600, height: 600)
        let result = frames([wide, wide, wide, wide, big, wide], expanded: 4)
        XCTAssertEqual(result[4], CGRect(x: 820, y: 20, width: 600, height: 600), "bottom at the area's bottom")
        XCTAssertEqual(result[0], CGRect(x: 1220, y: 767, width: 200, height: 113), "fits above: stays")
        XCTAssertEqual(result[1], CGRect(x: 1220, y: 639, width: 200, height: 113), "fits above: stays")
        XCTAssertEqual(result[2], CGRect(x: 1220, y: -108, width: 200, height: 113), "would be covered: below it")
        XCTAssertEqual(result[3], CGRect(x: 1220, y: -236, width: 200, height: 113))
        XCTAssertEqual(result[5], CGRect(x: 1220, y: -364, width: 200, height: 113), "the ones after follow")
    }

    func testExpandedLargerThanTheAreaFillsItFromTheTop() {
        let huge = CGSize(width: 2000, height: 2000)
        let result = frames([wide, huge], expanded: 1)
        XCTAssertEqual(result[1], CGRect(x: 560, y: 20, width: 860, height: 860))
        XCTAssertEqual(result[0], CGRect(x: 1220, y: -108, width: 200, height: 113), "the miniature above goes below")
    }

    /// Growing and moving up are one move; small again, the original order returns.
    func testGrowingMovesUpAtOnceAndCollapseRestoresTheOrder() {
        var s = stack(["a", "b", "c", "d"])
        _ = s.append("e", fullSize: CGSize(width: 600, height: 600))
        XCTAssertEqual(s.frame(of: "e")?.maxY, 368)
        s.arm("e")
        let grown = s.expand("e")
        XCTAssertEqual(grown["e"], CGRect(x: 820, y: 20, width: 600, height: 600))
        XCTAssertNil(grown["a"])
        XCTAssertNil(grown["b"])
        XCTAssertEqual(grown["c"]?.minY, -108)
        XCTAssertEqual(grown["d"]?.minY, -236)
        XCTAssertTrue(s.finishGrowing("e").isEmpty, "nothing left to catch up")
        let small = s.collapse("e")
        XCTAssertEqual(small["c"]?.minY, 511)
        XCTAssertEqual(small["d"]?.minY, 383)
        XCTAssertEqual(small["e"], CGRect(x: 1220, y: 168, width: 200, height: 200))
        XCTAssertEqual(s.items.map(\.id), ["a", "b", "c", "d", "e"])
    }

    // MARK: Nur eine armierte Miniatur

    func testArmingAnotherDisarmsTheFirst() {
        var s = stack(["a", "b"])
        XCTAssertTrue(s.arm("a"))
        XCTAssertTrue(s.arm("b"))
        XCTAssertEqual(s.phase(of: "a"), .mini)
        XCTAssertEqual(s.phase(of: "b"), .armed)
        XCTAssertEqual(s.items.filter { $0.phase == .armed }.count, 1)
        XCTAssertEqual(s.armedID, "b")
    }

    // MARK: Klick schließt nur vor dem Wachsen

    func testClickClosesOnlyBeforeGrowing() {
        var s = stack(["a"])
        XCTAssertEqual(s.phase(of: "a")?.closesOnClick, true, "mini")
        s.arm("a")
        XCTAssertEqual(s.phase(of: "a")?.closesOnClick, true, "within the 500 ms")
        _ = s.expand("a")
        XCTAssertEqual(s.phase(of: "a")?.closesOnClick, false, "growing")
        _ = s.finishGrowing("a")
        XCTAssertEqual(s.phase(of: "a")?.closesOnClick, false, "big")
        _ = s.collapse("a")
        XCTAssertEqual(s.phase(of: "a")?.closesOnClick, true, "mini again")
        s.beginLeaving("a")
        XCTAssertEqual(s.phase(of: "a")?.closesOnClick, false, "already leaving")
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

    // MARK: Restzeit (ohne Vorwarnung)

    func testLineShrinksWithRemainingTime() {
        let state = MiniatureRestIndicator.state(remaining: 10, total: 20, phase: .mini)
        XCTAssertEqual(state, MiniatureRestIndicator(lineVisible: true, lineFraction: 0.5, lineWarning: false))
    }

    /// No warning nudge and no fading: only the line turns yellow in the last 3 s.
    func testLineTurnsYellowInTheLastThreeSeconds() {
        XCTAssertFalse(MiniatureRestIndicator.state(remaining: 3, total: 20, phase: .mini).lineWarning)
        let end = MiniatureRestIndicator.state(remaining: 0, total: 20, phase: .mini)
        XCTAssertEqual(end, MiniatureRestIndicator(lineVisible: true, lineFraction: 0, lineWarning: true))
    }

    func testHoverTurnsTheLineWhiteAgain() {
        let state = MiniatureRestIndicator.state(remaining: 1, total: 20, phase: .armed)
        XCTAssertEqual(state, MiniatureRestIndicator(lineVisible: true, lineFraction: 0.05, lineWarning: false))
    }

    func testNoLineWhenExpandedLeavingOrNeverClosing() {
        XCTAssertFalse(MiniatureRestIndicator.state(remaining: 1, total: 20, phase: .expanded).lineVisible)
        XCTAssertFalse(MiniatureRestIndicator.state(remaining: 1, total: 20, phase: .leaving).lineVisible)
        XCTAssertEqual(MiniatureRestIndicator.state(remaining: 0, total: 0, phase: .mini), .neutral)
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
