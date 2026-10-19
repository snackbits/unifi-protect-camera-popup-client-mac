import XCTest
@testable import AppCore

final class StreamQualityTests: XCTestCase {
    func testDefaultIsMediumAndLabels() {
        XCTAssertEqual(StreamQuality.standard, .medium)
        XCTAssertEqual(StreamQuality.allCases.map(\.label), ["Hoch", "Mittel", "Niedrig"])
    }

    func testFallbackStartsWithItselfAndCoversAll() {
        for quality in StreamQuality.allCases {
            XCTAssertEqual(quality.fallbackOrder.first, quality.rawValue)
            XCTAssertEqual(Set(quality.fallbackOrder), ["high", "medium", "low"])
        }
        XCTAssertEqual(StreamQuality.medium.fallbackOrder, ["medium", "high", "low"])
    }

    func testV3KeepsQualityAndToleratesUnknownValues() throws {
        var ext = SettingsExtensionsV3()
        ext.mappings["a"] = .init(showNameAndTime: true, streamQuality: .low)
        let data = try JSONEncoder().encode(ext)
        XCTAssertEqual(SettingsExtensionsV3.decode(data)?.mappings["a"]?.streamQuality, .low)
        let odd = Data(#"{"mappings":{"a":{"streamQuality":"ultra","showNameAndTime":false}},"actions":{}}"#.utf8)
        let decoded = try XCTUnwrap(SettingsExtensionsV3.decode(odd))
        XCTAssertNil(decoded.mappings["a"]?.streamQuality)
        XCTAssertEqual(decoded.mappings["a"]?.showNameAndTime, false)
    }
}
