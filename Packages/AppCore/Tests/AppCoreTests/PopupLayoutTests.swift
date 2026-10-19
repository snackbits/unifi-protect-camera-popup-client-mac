import CoreGraphics
import XCTest
@testable import AppCore

final class PopupLayoutTests: XCTestCase {
    /// 1440 × 900 visible frame (menu bar already excluded), margin 16.
    private let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let topRight = PopupAnchor(horizontal: .trailing, vertical: .top)
    private var auto: CGSize {
        PopupSizing.size(override: .automatic, aspect: nil, visible: visible.size, margin: 16)
    }

    // MARK: Größe

    func testAutomaticSizeIs42PercentOfVisibleHeight() {
        XCTAssertEqual(auto, CGSize(width: 672, height: 378))
        // Portrait camera picture: width follows the aspect ratio.
        XCTAssertEqual(PopupSizing.size(override: .automatic, aspect: 0.75, visible: visible.size, margin: 16),
                       CGSize(width: 284, height: 378))
    }

    func testTwoAutomaticPopupsFitBelowEachOther() {
        let frames = PopupStackLayout.frames(sizes: [auto, auto], anchor: topRight, visible: visible, margin: 16)
        XCTAssertEqual(frames, [
            CGRect(x: 752, y: 506, width: 672, height: 378),
            CGRect(x: 752, y: 116, width: 672, height: 378),
        ])
    }

    func testAutomaticSizeFitsNarrowScreens() {
        let narrow = CGSize(width: 500, height: 1200)
        let size = PopupSizing.size(override: .automatic, aspect: 16.0 / 9.0, visible: narrow, margin: 16)
        XCTAssertEqual(size.width, 468)
        XCTAssertEqual(size.height, 263)
    }

    func testOneTypedValueKeepsAspectRatio() {
        XCTAssertEqual(PopupSizing.size(override: PopupSizeOverride(width: 640), aspect: nil, visible: visible.size, margin: 16),
                       CGSize(width: 640, height: 360))
        XCTAssertEqual(PopupSizing.size(override: PopupSizeOverride(height: 300), aspect: 4.0 / 3.0, visible: visible.size, margin: 16),
                       CGSize(width: 400, height: 300))
        XCTAssertEqual(PopupSizing.size(override: PopupSizeOverride(width: 500, height: 200), aspect: nil, visible: visible.size, margin: 16),
                       CGSize(width: 500, height: 200))
    }

    func testTinyTypedValuesAreRaisedToMinimum() {
        XCTAssertEqual(PopupSizing.size(override: PopupSizeOverride(width: 5, height: 3), aspect: nil, visible: visible.size, margin: 16),
                       CGSize(width: 40, height: 40))
    }

    func testBrokenAspectFallsBackTo16by9() {
        for aspect in [Double.nan, 0, -1, 100] {
            XCTAssertEqual(PopupSizing.validAspect(aspect), 16.0 / 9.0)
        }
    }

    func testMigrationTreatsOldDefaultAsAutomatic() {
        XCTAssertTrue(PopupSizeOverride.migrated(width: 480, height: 270).isAutomatic)
        XCTAssertEqual(PopupSizeOverride.migrated(width: 640, height: 360), PopupSizeOverride(width: 640, height: 360))
    }

    func testFieldTextParsing() {
        XCTAssertNil(PopupSizeOverride.value(fromText: ""))
        XCTAssertNil(PopupSizeOverride.value(fromText: "abc"))
        XCTAssertEqual(PopupSizeOverride.value(fromText: "640 px"), 640)
        XCTAssertEqual(PopupSizeOverride.value(fromText: "5"), 5, "no clamping while typing")
        XCTAssertNil(PopupSizeOverride.value(fromText: "0"))
        XCTAssertEqual(PopupSizeOverride.value(fromText: "99999999"), 99999)
    }

    func testLenientDecoding() throws {
        let decoded = try JSONDecoder().decode(PopupSizeOverride.self, from: Data(#"{"width":"x","height":-3}"#.utf8))
        XCTAssertTrue(decoded.isAutomatic)
        let kept = try JSONDecoder().decode(PopupSizeOverride.self, from: Data(#"{"width":700}"#.utf8))
        XCTAssertEqual(kept, PopupSizeOverride(width: 700))
    }

    // MARK: Stapel

    func testThreePopupsShrinkUniformly() {
        let frames = PopupStackLayout.frames(sizes: [auto, auto, auto], anchor: topRight, visible: visible, margin: 16)
        XCTAssertEqual(frames.count, 3)
        let heights = Set(frames.map(\.height))
        XCTAssertEqual(heights.count, 1)
        XCTAssertLessThan(frames[0].height, 378)
        XCTAssertGreaterThanOrEqual(frames[0].height, 160)
        // Aspect ratio stays (± rounding).
        XCTAssertEqual(frames[0].width / frames[0].height, 672.0 / 378.0, accuracy: 0.01)
        // All on screen, in order from the top, 12 apart.
        for frame in frames { XCTAssertTrue(visible.insetBy(dx: 16, dy: 16).contains(frame)) }
        XCTAssertEqual(frames[0].minY - frames[1].maxY, 12)
        XCTAssertEqual(frames[0].maxY, 884)
    }

    func testManyPopupsUseSecondColumnInsteadOfGoingBelowMinimum() {
        let frames = PopupStackLayout.frames(sizes: Array(repeating: auto, count: 6), anchor: topRight, visible: visible, margin: 16)
        XCTAssertTrue(frames.allSatisfy { $0.height >= 160 })
        // Column 1 at the right edge, column 2 to its left.
        XCTAssertEqual(frames[0].maxX, 1424)
        XCTAssertEqual(frames[3].maxX, frames[0].minX - 12)
        XCTAssertEqual(frames[3].maxY, frames[0].maxY)
        for frame in frames { XCTAssertTrue(visible.insetBy(dx: 16, dy: 16).contains(frame)) }
    }

    func testRemainingPopupsGrowBackAfterOneCloses() {
        let three = PopupStackLayout.frames(sizes: [auto, auto, auto], anchor: topRight, visible: visible, margin: 16)
        let two = PopupStackLayout.frames(sizes: [auto, auto], anchor: topRight, visible: visible, margin: 16)
        XCTAssertGreaterThan(two[0].height, three[0].height)
        XCTAssertEqual(two[0].height, 378, "back to the configured size, not larger")
    }

    func testOversizedSinglePopupFitsScreen() {
        let frames = PopupStackLayout.frames(sizes: [CGSize(width: 3000, height: 2000)], anchor: topRight, visible: visible, margin: 16)
        let frame = frames[0]
        XCTAssertTrue(visible.insetBy(dx: 16, dy: 16).contains(frame))
        XCTAssertEqual(frame.width / frame.height, 1.5, accuracy: 0.01)
    }

    func testSmallPopupsNeverGrow() {
        let small = CGSize(width: 200, height: 120)
        let frames = PopupStackLayout.frames(sizes: [small], anchor: topRight, visible: visible, margin: 16)
        XCTAssertEqual(frames[0].size, small)
    }

    func testBottomAnchorStacksUpward() {
        let anchor = PopupAnchor(horizontal: .leading, vertical: .bottom)
        let frames = PopupStackLayout.frames(sizes: [auto, auto], anchor: anchor, visible: visible, margin: 16)
        XCTAssertEqual(frames[0], CGRect(x: 16, y: 16, width: 672, height: 378))
        XCTAssertEqual(frames[1].minY, frames[0].maxY + 12)
    }

    func testMiddleAnchorCentersTheStack() {
        let anchor = PopupAnchor(horizontal: .center, vertical: .middle)
        let frames = PopupStackLayout.frames(sizes: [auto, auto], anchor: anchor, visible: visible, margin: 16)
        let union = frames[0].union(frames[1])
        XCTAssertEqual(union.midY, 450, accuracy: 1)
        XCTAssertEqual(union.midX, 720, accuracy: 1)
        XCTAssertGreaterThan(frames[0].minY, frames[1].minY, "first popup on top")
    }

    func testScreenWithOffsetOrigin() {
        let second = CGRect(x: 1440, y: -200, width: 1920, height: 1055)
        let frames = PopupStackLayout.frames(sizes: [auto], anchor: topRight, visible: second, margin: 16)
        XCTAssertEqual(frames[0].maxX, 1440 + 1920 - 16)
        XCTAssertEqual(frames[0].maxY, -200 + 1055 - 16)
    }

    func testTalkButtonFallsBackToMicrophoneInNarrowPopups() {
        // Ton abspielen + three buttons + two-line talk button (≈ 207) = 387 wide.
        XCTAssertTrue(PopupPillFit.talkButtonFits(popupWidth: 470, circles: 4, talkWidth: 207))
        XCTAssertFalse(PopupPillFit.talkButtonFits(popupWidth: 284, circles: 4, talkWidth: 207))
        XCTAssertTrue(PopupPillFit.talkButtonFits(popupWidth: 284, circles: 1, talkWidth: 207))
        XCTAssertTrue(PopupPillFit.talkButtonFits(popupWidth: 284, circles: 4, talkWidth: 40), "microphone only fits the smallest 16:9 popup")
    }

    func testEmptyInput() {
        XCTAssertTrue(PopupStackLayout.frames(sizes: [], anchor: topRight, visible: visible, margin: 16).isEmpty)
    }

    // MARK: Miniatur

    /// 16:9 full size → 200 × 113 miniature.
    private let wide = CGSize(width: 672, height: 378)

    private func miniFrames(_ sizes: [CGSize], expanded: Int? = nil, side: PopupAnchor.Horizontal) -> [CGRect] {
        PopupStackLayout.miniatureFrames(fullSizes: sizes, expandedIndex: expanded, side: side, visible: visible, margin: 16)
    }

    func testOneMiniatureRightAndLeft() {
        XCTAssertEqual(miniFrames([wide], side: .trailing), [CGRect(x: 1224, y: 771, width: 200, height: 113)])
        XCTAssertEqual(miniFrames([wide], side: .leading), [CGRect(x: 16, y: 771, width: 200, height: 113)])
    }

    func testMiniatureHeightFollowsAspectRatio() {
        let portrait = CGSize(width: 300, height: 400)
        XCTAssertEqual(miniFrames([portrait], side: .trailing)[0].size, CGSize(width: 200, height: 267))
    }

    func testThreeMiniaturesStackDownwardWithGap() {
        let right = miniFrames([wide, wide, wide], side: .trailing)
        XCTAssertEqual(right, [
            CGRect(x: 1224, y: 771, width: 200, height: 113),
            CGRect(x: 1224, y: 648, width: 200, height: 113),
            CGRect(x: 1224, y: 525, width: 200, height: 113),
        ])
        let left = miniFrames([wide, wide, wide], side: .leading)
        XCTAssertEqual(left.map(\.minX), [16, 16, 16])
        XCTAssertEqual(left.map(\.minY), [771, 648, 525])
    }

    func testExpandedKeepsTopOuterCornerAndPushesFollowersDown() {
        let right = miniFrames([wide, wide, wide], expanded: 1, side: .trailing)
        XCTAssertEqual(right[0], CGRect(x: 1224, y: 771, width: 200, height: 113))
        XCTAssertEqual(right[1], CGRect(x: 752, y: 383, width: 672, height: 378))
        XCTAssertEqual(right[1].maxX, 1424, "top right corner stays where the miniature's was")
        XCTAssertEqual(right[1].maxY, 761)
        XCTAssertEqual(right[2], CGRect(x: 1224, y: 260, width: 200, height: 113))

        let left = miniFrames([wide, wide], expanded: 0, side: .leading)
        XCTAssertEqual(left[0], CGRect(x: 16, y: 506, width: 672, height: 378))
        XCTAssertEqual(left[1], CGRect(x: 16, y: 383, width: 200, height: 113))
    }

    func testOverflowRunsBelowScreenWithoutSecondColumn() {
        let frames = miniFrames(Array(repeating: wide, count: 10), side: .trailing)
        XCTAssertEqual(Set(frames.map(\.minX)), [1224])
        XCTAssertTrue(frames.allSatisfy { $0.size == CGSize(width: 200, height: 113) }, "nothing shrinks")
        XCTAssertEqual(frames[7].minY, 771 - 7 * 123)
        XCTAssertLessThan(frames[9].maxY, visible.minY)
    }

    func testOversizedExpandedFitsVisibleAreaKeepingAspect() {
        let wideOne = miniFrames([CGSize(width: 3000, height: 1000)], expanded: 0, side: .trailing)[0]
        XCTAssertEqual(wideOne, CGRect(x: 16, y: 415, width: 1408, height: 469))
        let tall = miniFrames([CGSize(width: 500, height: 2000)], expanded: 0, side: .leading)[0]
        XCTAssertEqual(tall, CGRect(x: 16, y: 16, width: 217, height: 868))
    }

    func testMiniatureEmptyInput() {
        XCTAssertTrue(miniFrames([], side: .trailing).isEmpty)
    }

    func testOffscreenFrameBeyondOuterEdge() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 925)
        let right = CGRect(x: 1224, y: 771, width: 200, height: 113)
        XCTAssertEqual(PopupStackLayout.offscreenFrame(for: right, side: .trailing, screenFrame: screen),
                       CGRect(x: 1470, y: 771, width: 200, height: 113))
        let left = CGRect(x: 16, y: 771, width: 200, height: 113)
        XCTAssertEqual(PopupStackLayout.offscreenFrame(for: left, side: .leading, screenFrame: screen),
                       CGRect(x: -230, y: 771, width: 200, height: 113))
        let second = CGRect(x: 1440, y: -200, width: 1920, height: 1080)
        XCTAssertEqual(PopupStackLayout.offscreenFrame(for: left, side: .leading, screenFrame: second).minX, 1440 - 230)
        XCTAssertEqual(PopupStackLayout.offscreenFrame(for: right, side: .trailing, screenFrame: second).minX, 3360 + 30)
    }

    // MARK: Position

    func testLegacyPositionValuesMigrateToSides() {
        for raw in ["topLeft", "middleLeft", "bottomLeft", "left"] {
            XCTAssertEqual(PopupAnchor.Horizontal.side(fromPositionRawValue: raw), .leading, raw)
        }
        for raw in ["topRight", "middleRight", "bottomRight", "topCenter", "center", "bottomCenter", "right", "", "sideways"] {
            XCTAssertEqual(PopupAnchor.Horizontal.side(fromPositionRawValue: raw), .trailing, raw)
        }
    }

    // MARK: Layout-Modus

    func testPopupLayoutModeLabelsAndFallback() throws {
        XCTAssertEqual(PopupLayoutMode.allCases.map(\.label), ["Miniatur", "Voll"])
        struct Box: Codable { let mode: PopupLayoutMode }
        let unknown = try JSONDecoder().decode(Box.self, from: Data(#"{"mode":"grid"}"#.utf8))
        XCTAssertEqual(unknown.mode, .miniature)
        let roundTrip = try JSONDecoder().decode(Box.self, from: JSONEncoder().encode(Box(mode: .full)))
        XCTAssertEqual(roundTrip.mode, .full)
    }
}
