import XCTest
@testable import AppCore

final class MuteDurationTests: XCTestCase {
    func testDefaultsMatchTemplate() {
        XCTAssertEqual(MuteDuration.defaultShort.shortLabel, "15 Min.")
        XCTAssertEqual(MuteDuration.defaultLong.shortLabel, "1 Std.")
        XCTAssertEqual(MuteDuration.defaultShort.longLabel, "15 Minuten")
        XCTAssertEqual(MuteDuration.defaultLong.longLabel, "1 Stunde")
        XCTAssertEqual(MuteDuration.defaultShort.seconds, 900)
        XCTAssertEqual(MuteDuration.defaultLong.seconds, 3600)
        XCTAssertEqual(MuteDuration.Unit.minutes.label, "Minuten")
        XCTAssertEqual(MuteDuration.Unit.hours.label, "Stunden")
    }

    func testSingularAndPlural() {
        XCTAssertEqual(MuteDuration(value: 1, unit: .minutes).longLabel, "1 Minute")
        XCTAssertEqual(MuteDuration(value: 2, unit: .hours).longLabel, "2 Stunden")
        XCTAssertEqual(MuteDuration(value: 2, unit: .hours).shortLabel, "2 Std.")
    }

    func testValuesAreClamped() {
        XCTAssertEqual(MuteDuration(value: 0, unit: .minutes).value, 1)
        XCTAssertEqual(MuteDuration(value: -3, unit: .minutes).value, 1)
        XCTAssertEqual(MuteDuration(value: 5000, unit: .hours).value, 999)
        XCTAssertEqual(MuteDuration.defaultShort.withValue(30), MuteDuration(value: 30, unit: .minutes))
    }

    // Review Focus 4
    func testParseRejectsGarbageAndClamps() {
        XCTAssertNil(MuteDuration.parseValue(""))
        XCTAssertNil(MuteDuration.parseValue("   "))
        XCTAssertNil(MuteDuration.parseValue("12a"))
        XCTAssertNil(MuteDuration.parseValue("-5"))
        XCTAssertNil(MuteDuration.parseValue("١٢"))
        XCTAssertEqual(MuteDuration.parseValue(" 30 "), 30)
        XCTAssertEqual(MuteDuration.parseValue("0"), 1)
        XCTAssertEqual(MuteDuration.parseValue("5000"), 999)
        XCTAssertEqual(MuteDuration.parseValue("99999999999999999999999"), 999)
    }

    func testLenientDecodingAndRoundTrip() throws {
        let broken = try JSONDecoder().decode(MuteDuration.self, from: Data(#"{"value":0,"unit":"weeks"}"#.utf8))
        XCTAssertEqual(broken, MuteDuration(value: 1, unit: .minutes))
        let roundTrip = try JSONDecoder().decode(MuteDuration.self, from: JSONEncoder().encode(MuteDuration.defaultLong))
        XCTAssertEqual(roundTrip, .defaultLong)
    }
}
