import XCTest
@testable import AppCore

final class PiperVoiceCatalogTests: XCTestCase {
    func testEveryGermanVoiceIsListedOnce() {
        XCTAssertEqual(PiperVoiceCatalog.all.map(\.id), [
            "de_DE-eva_k-x_low", "de_DE-karlsson-low", "de_DE-kerstin-low", "de_DE-mls-medium", "de_DE-pavoque-low",
            "de_DE-ramona-low", "de_DE-thorsten-low", "de_DE-thorsten-medium", "de_DE-thorsten-high",
            "de_DE-thorsten_emotional-medium",
        ])
        XCTAssertEqual(Set(PiperVoiceCatalog.all.map(\.id)).count, PiperVoiceCatalog.all.count)
    }

    func testNonCommercialVoicesAreNotOffered() {
        XCTAssertEqual(PiperVoiceCatalog.excluded.map(\.id), ["de_DE-pavoque-low"])
        XCTAssertFalse(PiperVoiceCatalog.offered.contains { $0.id == "de_DE-pavoque-low" })
        XCTAssertNil(PiperVoiceCatalog.voice(id: "de_DE-pavoque-low"))
        XCTAssertNil(PiperVoiceCatalog.voice(id: "en_US-lessac-medium"))
        XCTAssertEqual(PiperVoiceCatalog.offered.count, 9)
        XCTAssertTrue(PiperVoiceCatalog.offered.allSatisfy { $0.license.allowsRedistribution })
    }

    func testDefaultVoiceIsThorstenMedium() {
        let voice = PiperVoiceCatalog.defaultVoice
        XCTAssertEqual(voice.id, "de_DE-thorsten-medium")
        XCTAssertEqual(voice.label, "Thorsten · mittel")
        XCTAssertEqual(voice.license, .thorstenCC0)
        // Same pin as piper/scripts/fetch.sh (smoke test and integration test use that file).
        XCTAssertEqual(voice.model.sha256, "7e64762d8e5118bb578f2eea6207e1a35a8e0c30595010b666f983fc87bb7819")
        XCTAssertEqual(voice.config.sha256, "974adee790533adb273a1ac88f49027d2a1b8f0f2cf4905954a4791e79264e85")
    }

    func testFilesArePinnedToTheRevision() {
        for voice in PiperVoiceCatalog.all {
            for file in [voice.model, voice.config] {
                XCTAssertEqual(file.sha256.count, 64, file.path)
                XCTAssertNotNil(file.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression), file.path)
                XCTAssertGreaterThan(file.size, 0)
                XCTAssertTrue(file.url.absoluteString.hasPrefix(
                    "https://huggingface.co/rhasspy/piper-voices/resolve/c10ece1aade47bb51c153c893d14e5bf8e5b7117/de/de_DE/"))
                XCTAssertFalse(file.url.absoluteString.contains("/main/"))
            }
            XCTAssertEqual(voice.config.fileName, voice.model.fileName + ".json")
            XCTAssertEqual(voice.model.fileName, voice.id + ".onnx")
        }
    }

    func testSpeakers() throws {
        let emotional = try XCTUnwrap(PiperVoiceCatalog.voice(id: "de_DE-thorsten_emotional-medium"))
        XCTAssertEqual(emotional.speakerCount, 8)
        XCTAssertEqual(emotional.defaultSpeaker, 4)
        XCTAssertEqual(emotional.speakerLabel(4), "neutral")
        XCTAssertEqual(emotional.speakerLabel(7), "flüsternd")
        XCTAssertNil(emotional.speakerLabel(8))
        let mls = try XCTUnwrap(PiperVoiceCatalog.voice(id: "de_DE-mls-medium"))
        XCTAssertEqual(mls.speakerCount, 236)
        XCTAssertEqual(mls.speakerLabel(0), "Sprecher 1")
        XCTAssertEqual(mls.speakerLabel(235), "Sprecher 236")
        XCTAssertNil(PiperVoiceCatalog.defaultVoice.speakerLabel(0))
        XCTAssertFalse(PiperVoiceCatalog.defaultVoice.isMultiSpeaker)
    }

    func testDownloadSizeIsModelPlusConfig() throws {
        let high = try XCTUnwrap(PiperVoiceCatalog.voice(id: "de_DE-thorsten-high"))
        XCTAssertEqual(high.downloadSize, 113_895_201 + 4_875)
        XCTAssertEqual(high.label, "Thorsten · hoch")
        XCTAssertEqual(PiperVoiceCatalog.voice(id: "de_DE-eva_k-x_low")?.label, "Eva K. · sehr niedrig")
    }
}
