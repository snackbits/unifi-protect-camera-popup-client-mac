import AppKit
import XCTest
@testable import AppCore

final class AppearanceModeTests: XCTestCase {
    func testLabelsAndAppearanceNames() {
        XCTAssertEqual(AppearanceMode.allCases.map(\.label), ["System", "Hell", "Dunkel"])
        XCTAssertNil(AppearanceMode.system.appearanceName)
        XCTAssertEqual(AppearanceMode.light.appearanceName, .aqua)
        XCTAssertEqual(AppearanceMode.dark.appearanceName, .darkAqua)
    }

    // Review Focus 1
    func testUnknownValueFallsBackToSystem() throws {
        struct Box: Codable { let mode: AppearanceMode }
        let box = try JSONDecoder().decode(Box.self, from: Data(#"{"mode":"sepia"}"#.utf8))
        XCTAssertEqual(box.mode, .system)
        let roundTrip = try JSONDecoder().decode(Box.self, from: JSONEncoder().encode(Box(mode: .dark)))
        XCTAssertEqual(roundTrip.mode, .dark)
    }
}
