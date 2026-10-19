import AppCore
import XCTest

final class SettingsExtensionsV3Tests: XCTestCase {
    private let entry = "11111111-1111-1111-1111-111111111111"
    private let action = "22222222-2222-2222-2222-222222222222"
    private let sound = UUID(uuidString: "6F0C6A52-4C4B-4E58-9B1E-2F3C1C0A0001")!

    /// What the installed 1.2.0 build writes to `settingsExtensionsV2` on every launch: the Phase-4
    /// fields only.
    private var v2WrittenByOldBuild: SettingsExtensions? {
        SettingsExtensions.decode(Data("""
        {"mappings":{"\(entry)":{"protectCameraId":"cam","triggers":["ring"],"webhookTriggerEnabled":false,"chimeOnOpen":true}},
         "actions":{"\(action)":{"icon":"door","confirmBeforeRun":true}}}
        """.utf8))
    }

    /// The main blob after the old build rewrote it: no Phase-5 fields, so the decoder falls back
    /// to its defaults (size migrated from the mirrored width/height).
    private var baseAfterOldBuild: Phase5MappingFields {
        Phase5MappingFields(showNameAndTime: false, sizeOverride: .migrated(width: 600, height: 400), eventRules: [])
    }

    private func v3Data(rule: EventRule) throws -> Data {
        let v3 = SettingsExtensionsV3(
            mappings: [entry: .init(showNameAndTime: true, size: PopupSizeOverride(width: 600, height: nil), eventRules: EventRuleList([rule]))],
            actions: [action: .init(soundId: sound.uuidString)]
        )
        return try JSONEncoder().encode(v3)
    }

    func testV3RestoresFieldsAfterOldBuildRewroteV2AndMainBlob() throws {
        let rule = EventRule(kind: "vehicle", webhook: EventRuleWebhook(url: "https://example.com/hook"), bearerToken: "secret", delaySeconds: 5)
        let data = try v3Data(rule: rule)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("secret"))
        let v3 = try XCTUnwrap(SettingsExtensionsV3.decode(data))
        let v2 = try XCTUnwrap(v2WrittenByOldBuild)

        let fields = SettingsMerge.mapping(entryId: entry, base: baseAfterOldBuild, v2: v2, v3: v3)
        XCTAssertTrue(fields.showNameAndTime)
        XCTAssertEqual(fields.sizeOverride, PopupSizeOverride(width: 600, height: nil))
        XCTAssertEqual(fields.eventRules.map(\.id), [rule.id])
        XCTAssertEqual(fields.eventRules.first?.kind, "vehicle")
        XCTAssertEqual(fields.eventRules.first?.delaySeconds, 5)
        XCTAssertEqual(fields.eventRules.first?.bearerToken, "", "tokens come from the keychain")

        XCTAssertEqual(SettingsMerge.soundId(actionId: action, base: nil, v2: v2, v3: v3), sound)
    }

    func testV3ActionEntryIsAuthoritativeAndV2OnlyWhenItCarriesAnId() throws {
        let v3NoSound = SettingsExtensionsV3(actions: [action: .init(soundId: nil)])
        let v2WithSound = SettingsExtensions(actions: [action: .init(icon: "door", soundId: sound.uuidString)])
        XCTAssertNil(SettingsMerge.soundId(actionId: action, base: sound, v2: v2WithSound, v3: v3NoSound))
        // No V3 entry: a V2 entry from the old build (no soundId) does not reset the main blob's value.
        XCTAssertEqual(SettingsMerge.soundId(actionId: action, base: sound, v2: v2WrittenByOldBuild, v3: nil), sound)
        XCTAssertEqual(SettingsMerge.soundId(actionId: action, base: nil, v2: v2WithSound, v3: SettingsExtensionsV3()), sound)
    }

    func testWithoutV3TheOldV2AndMainBlobAreKept() {
        let fields = SettingsMerge.mapping(entryId: entry, base: baseAfterOldBuild, v2: v2WrittenByOldBuild, v3: nil)
        XCTAssertEqual(fields, baseAfterOldBuild)
    }

    func testDecodingIsLenient() throws {
        XCTAssertNil(SettingsExtensionsV3.decode(nil))
        XCTAssertNil(SettingsExtensionsV3.decode(Data("garbage".utf8)))
        let v3 = try XCTUnwrap(SettingsExtensionsV3.decode(Data("""
        {"mappings":{"\(entry)":{"showNameAndTime":"yes","size":{"width":300},"eventRules":[{"broken":1},{"kind":"ring"}]}},"actions":7}
        """.utf8)))
        XCTAssertNil(v3.mappings[entry]?.showNameAndTime)
        XCTAssertEqual(v3.mappings[entry]?.size, PopupSizeOverride(width: 300))
        XCTAssertEqual(v3.mappings[entry]?.eventRules?.rules.map(\.kind), ["ring"])
        XCTAssertEqual(v3.actions, [:])
    }

    func testTypedSizeIsMirroredIntoLegacyDimensions() {
        let typed = SettingsMerge.legacyDimensions(size: PopupSizeOverride(width: 600, height: 400), hasCrop: false, width: 480, height: 270)
        XCTAssertEqual(typed.width, 600)
        XCTAssertEqual(typed.height, 400)
        // Below the minimum the popup is 40 pt; the older build gets the same.
        let tiny = SettingsMerge.legacyDimensions(size: PopupSizeOverride(width: 10, height: 400), hasCrop: false, width: 480, height: 270)
        XCTAssertEqual(tiny.width, 40)
        // Automatic, one side only, or a crop: unchanged.
        for (size, crop) in [(PopupSizeOverride.automatic, false), (PopupSizeOverride(width: 600), false), (PopupSizeOverride(width: 600, height: 400), true)] {
            let kept = SettingsMerge.legacyDimensions(size: size, hasCrop: crop, width: 480, height: 270)
            XCTAssertEqual(kept.width, 480)
            XCTAssertEqual(kept.height, 270)
        }
        // Round trip with the main blob's migration: a mirrored typed size stays typed.
        XCTAssertEqual(PopupSizeOverride.migrated(width: typed.width, height: typed.height), PopupSizeOverride(width: 600, height: 400))
    }
}
