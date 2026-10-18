import AppKit
import XCTest
@testable import AppCore

final class DesignTokensTests: XCTestCase {
    func testValuesFromTemplate() {
        XCTAssertEqual(Tokens.accent, ThemeColor(0x4B3FD1, 0x5B4FE0))
        XCTAssertEqual(Tokens.win, ThemeColor(0xFBFBFD, 0x26262C))
        XCTAssertEqual(Tokens.tabOn, ThemeColor(0xE4E2F8, 0x3A3566))
        XCTAssertEqual(Tokens.chipOff, ThemeColor(0xFFFFFF, 0x34343C))
        XCTAssertEqual(Tokens.mainChipOff, ThemeColor(0xFFFFFF, 0x2E2E35))
        XCTAssertEqual(Tokens.pill.dark, RGBA(0x141518, alpha: 0.84))
        XCTAssertEqual(Tokens.overlay.light, RGBA(0x000000, alpha: 0.62))
        XCTAssertEqual(Tokens.overlay.light, Tokens.overlay.dark)
    }

    func testDynamicColorFollowsAppearance() throws {
        XCTAssertEqual(try resolvedRed(Tokens.win, .aqua), 0xFB)
        XCTAssertEqual(try resolvedRed(Tokens.win, .darkAqua), 0x26)
        XCTAssertEqual(try resolvedRed(Tokens.accent, .darkAqua), 0x5B)
    }

    private func resolvedRed(_ token: ThemeColor, _ name: NSAppearance.Name) throws -> Int {
        let appearance = try XCTUnwrap(NSAppearance(named: name))
        var red: CGFloat = -1
        appearance.performAsCurrentDrawingAppearance {
            red = token.nsColor.usingColorSpace(.sRGB)?.redComponent ?? -1
        }
        return Int((red * 255).rounded())
    }
}
