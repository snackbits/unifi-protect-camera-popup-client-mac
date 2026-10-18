import XCTest
@testable import AppCore

final class SettingsExtensionsTests: XCTestCase {
    private func sample() -> SettingsExtensions {
        SettingsExtensions(
            protectHost: "192.168.1.1",
            protectCertificateFingerprint: "AB:CD",
            protectConsoleName: "UDM Pro",
            muteSchedule: MuteSchedule(globalUntil: Date(timeIntervalSince1970: 2_000_000_000), cameras: ["A": Date(timeIntervalSince1970: 2_000_000_100)]),
            muteShort: MuteDuration(value: 5, unit: .minutes),
            muteLong: MuteDuration(value: 2, unit: .hours),
            appearance: .dark,
            mappings: ["A": .init(protectCameraId: "cam", triggers: ["ring"], webhookTriggerEnabled: false, chimeOnOpen: true)],
            actions: ["X": .init(icon: "door", confirmBeforeRun: true)]
        )
    }

    func testRoundTrip() throws {
        let data = try JSONEncoder().encode(sample())
        XCTAssertEqual(SettingsExtensions.decode(data), sample())
    }

    func testMissingDataIsNil() {
        XCTAssertNil(SettingsExtensions.decode(nil))
    }

    func testGarbledDataIsIgnored() {
        XCTAssertNil(SettingsExtensions.decode(Data("not json".utf8)))
        XCTAssertNil(SettingsExtensions.decode(Data("[1,2]".utf8)))
    }

    func testBrokenFieldDoesNotDiscardOthers() throws {
        let json = #"{"protectHost":42,"appearance":"dark","mappings":{"A":{"chimeOnOpen":"yes","protectCameraId":"cam"}},"actions":"junk"}"#
        let decoded = try XCTUnwrap(SettingsExtensions.decode(Data(json.utf8)))
        XCTAssertNil(decoded.protectHost)
        XCTAssertEqual(decoded.appearance, .dark)
        XCTAssertEqual(decoded.mappings["A"]?.protectCameraId, "cam")
        XCTAssertNil(decoded.mappings["A"]?.chimeOnOpen)
        XCTAssertTrue(decoded.actions.isEmpty)
    }

    func testPrunedDropsStaleIds() {
        let pruned = sample().pruned(validMappings: ["B"], validActions: ["X"])
        XCTAssertTrue(pruned.mappings.isEmpty)
        XCTAssertEqual(pruned.actions.keys.sorted(), ["X"])
        XCTAssertEqual(pruned.appearance, .dark)
    }
}
