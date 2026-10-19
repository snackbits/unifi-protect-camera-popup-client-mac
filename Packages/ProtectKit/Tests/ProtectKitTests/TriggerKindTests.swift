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

    func testChipsShowOnlyEnabledKindsInTemplateOrder() {
        let enabled: Set<TriggerKind> = [.ring, .person, .package, .animal, .speak, .glassBreak, .motion,
                                         .personLine, .animalLine]
        let chips = TriggerKind.chips(enabled: enabled)
        XCTAssertEqual(chips.detections.map(\.label),
                       ["Klingel", "Person", "Paket", "Tier", "Sprache", "Glasbruch", "Bewegung"])
        XCTAssertEqual(chips.lines, [.personLine, .animalLine])
        XCTAssertEqual(chips.lines.map(\.chipLabel), ["Person", "Tier"])
    }

    func testChipsWithoutSmartDetections() {
        let chips = TriggerKind.chips(enabled: [.motion])
        XCTAssertEqual(chips.detections, [.motion])
        XCTAssertEqual(chips.lines, [])
    }

    func testLineVariantsAndBase() {
        XCTAssertEqual(TriggerKind.person.lineVariant, .personLine)
        XCTAssertEqual(TriggerKind.vehicle.lineVariant, .vehicleLine)
        XCTAssertEqual(TriggerKind.animal.lineVariant, .animalLine)
        XCTAssertNil(TriggerKind.licensePlate.lineVariant)
        XCTAssertNil(TriggerKind.personLine.lineVariant)
        XCTAssertEqual(TriggerKind.vehicleLine.base, .vehicle)
        XCTAssertEqual(TriggerKind.ring.base, .ring)
        XCTAssertEqual(TriggerKind.personLine.label, "Person überquert Linie")
        XCTAssertEqual(TriggerKind.person.chipLabel, "Person")
    }

    func testDisplayOrderCoversAllKindsOnce() {
        XCTAssertEqual(TriggerKind.displayOrder.count, TriggerKind.allCases.count)
        XCTAssertEqual(Set(TriggerKind.displayOrder), Set(TriggerKind.allCases))
    }
}
