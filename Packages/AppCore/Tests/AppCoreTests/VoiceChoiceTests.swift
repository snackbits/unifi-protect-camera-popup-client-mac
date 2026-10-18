import XCTest
@testable import AppCore

final class VoiceChoiceTests: XCTestCase {
    private func voice(_ name: String, _ language: String = "de-DE", quality: Int = 1) -> VoiceChoice.Candidate {
        VoiceChoice.Candidate(identifier: "com.apple.\(name).\(quality).\(language)", name: name, language: language, quality: quality)
    }

    func testAnnaWinsInHerBestQuality() {
        let pick = VoiceChoice.pick(from: [voice("Petra", quality: 3), voice("Anna"), voice("Anna", quality: 2), voice("Samantha", "en-US", quality: 3)])
        XCTAssertEqual(pick, voice("Anna", quality: 2))
        XCTAssertEqual(VoiceChoice.fieldLabel(pick), "Anna · macOS")
        XCTAssertNil(VoiceChoice.hint(pick))
    }

    func testWithoutAnnaTheBestGermanVoice() {
        let pick = VoiceChoice.pick(from: [voice("Yannick"), voice("Petra", "de-AT", quality: 2), voice("Helena", quality: 2)])
        XCTAssertEqual(pick?.name, "Helena", "same quality: de-DE before de-AT")
        XCTAssertEqual(VoiceChoice.fieldLabel(pick), "Helena · macOS")
        XCTAssertEqual(VoiceChoice.hint(pick)?.contains("„Helena“"), true)
    }

    func testNoGermanVoice() {
        let pick = VoiceChoice.pick(from: [voice("Samantha", "en-US")])
        XCTAssertNil(pick)
        XCTAssertEqual(VoiceChoice.fieldLabel(pick), "Keine deutsche Stimme installiert")
        XCTAssertNotNil(VoiceChoice.hint(pick))
    }
}
