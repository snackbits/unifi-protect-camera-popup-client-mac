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

    func testPhase5FieldsRoundTripAndStayLenient() throws {
        let rule = EventRule(kind: "ring", webhook: EventRuleWebhook(url: "https://ha.local/x"), bearerToken: "t0k3n", delaySeconds: 5)
        let ext = SettingsExtensions(
            mappings: ["A": .init(showNameAndTime: true, size: PopupSizeOverride(width: 640), eventRules: EventRuleList([rule]))],
            actions: ["X": .init(icon: "door", soundId: "6F0C6A52-4C4B-4E58-9B1E-2F3C1C0A0001")]
        )
        let data = try JSONEncoder().encode(ext)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("t0k3n"))
        let back = try XCTUnwrap(SettingsExtensions.decode(data))
        XCTAssertEqual(back.mappings["A"]?.showNameAndTime, true)
        XCTAssertEqual(back.mappings["A"]?.size, PopupSizeOverride(width: 640))
        XCTAssertEqual(back.mappings["A"]?.eventRules?.rules.map(\.id), [rule.id])
        XCTAssertEqual(back.actions["X"]?.soundId, "6F0C6A52-4C4B-4E58-9B1E-2F3C1C0A0001")

        // Written by the Phase-2–4 build: no new keys → nil (caller migrates); garbage → nil, rest kept.
        let old = try XCTUnwrap(SettingsExtensions.decode(Data(#"{"mappings":{"A":{"chimeOnOpen":true,"size":"big","eventRules":7}}}"#.utf8)))
        XCTAssertEqual(old.mappings["A"]?.chimeOnOpen, true)
        XCTAssertNil(old.mappings["A"]?.showNameAndTime)
        XCTAssertNil(old.mappings["A"]?.size)
        XCTAssertNil(old.mappings["A"]?.eventRules)
    }

    func testPrunedDropsStaleIds() {
        let pruned = sample().pruned(validMappings: ["B"], validActions: ["X"])
        XCTAssertTrue(pruned.mappings.isEmpty)
        XCTAssertEqual(pruned.actions.keys.sorted(), ["X"])
        XCTAssertEqual(pruned.appearance, .dark)
    }
}
