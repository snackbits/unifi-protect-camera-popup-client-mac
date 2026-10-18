import XCTest
@testable import ProtectKit

final class TriggerKindTests: XCTestCase {
    func testWireValuesMapToKinds() {
        XCTAssertEqual(TriggerKind(wireValue: "person"), .person)
        XCTAssertEqual(TriggerKind(wireValue: "vehicle"), .vehicle)
        XCTAssertEqual(TriggerKind(wireValue: "animal"), .animal)
        XCTAssertEqual(TriggerKind(wireValue: "package"), .package)
        XCTAssertEqual(TriggerKind(wireValue: "licensePlate"), .licensePlate)
        XCTAssertEqual(TriggerKind(wireValue: "face"), .face)
        XCTAssertEqual(TriggerKind(wireValue: "alrmSpeak"), .speak)
        XCTAssertEqual(TriggerKind(wireValue: "alrmBark"), .bark)
        XCTAssertEqual(TriggerKind(wireValue: "alrmBabyCry"), .babyCry)
        XCTAssertEqual(TriggerKind(wireValue: "alrmGlassBreak"), .glassBreak)
        XCTAssertEqual(TriggerKind(wireValue: "alrmSmoke"), .smoke)
        XCTAssertEqual(TriggerKind(wireValue: "smoke_cmonx"), .smoke)
        XCTAssertEqual(TriggerKind(wireValue: "alrmCmonx"), .carbonMonoxide)
        XCTAssertEqual(TriggerKind(wireValue: "alrmSiren"), .siren)
        XCTAssertEqual(TriggerKind(wireValue: "alrmCarHorn"), .carHorn)
        XCTAssertEqual(TriggerKind(wireValue: "alrmBurglar"), .burglar)
        XCTAssertEqual(TriggerKind(wireValue: "car"), .vehicle)
        XCTAssertEqual(TriggerKind(wireValue: "pet"), .animal)
        XCTAssertNil(TriggerKind(wireValue: "somethingNew"))
    }

    func testOrderedListsRingFirstAndContainsAll() {
        XCTAssertEqual(TriggerKind.ordered.first, .ring)
        XCTAssertEqual(Set(TriggerKind.ordered), Set(TriggerKind.allCases))
    }

    func testLabelsAreGerman() {
        XCTAssertEqual(TriggerKind.ring.label, "Klingel")
        XCTAssertEqual(TriggerKind.speak.label, "Sprache")
        XCTAssertEqual(TriggerKind.glassBreak.label, "Glasbruch")
    }

    func testCodableRoundTrip() throws {
        let data = try JSONEncoder().encode([TriggerKind.ring, .person])
        XCTAssertEqual(String(data: data, encoding: .utf8), "[\"ring\",\"person\"]")
        XCTAssertEqual(try JSONDecoder().decode([TriggerKind].self, from: data), [.ring, .person])
    }
}
