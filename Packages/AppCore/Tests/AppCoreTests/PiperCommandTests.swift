import XCTest
@testable import AppCore

final class PiperCommandTests: XCTestCase {
    private let installation = PiperInstallation(contents: URL(fileURLWithPath: "/Applications/UniFi Camera Popup.app/Contents"))

    func testInstallationPathsInsideTheBundle() {
        XCTAssertEqual(installation.executable.path, "/Applications/UniFi Camera Popup.app/Contents/Helpers/piper/piper")
        XCTAssertEqual(installation.espeakData.path, "/Applications/UniFi Camera Popup.app/Contents/Resources/piper/espeak-ng-data")
    }

    func testArgumentsForASingleSpeakerVoice() {
        let voices = URL(fileURLWithPath: "/Users/x/Library/Application Support/UniFi Camera Popup/Voices/de_DE-thorsten-medium")
        let files = PiperVoiceFiles(voice: PiperVoiceCatalog.defaultVoice, folder: voices)
        let output = URL(fileURLWithPath: "/tmp/out.wav")
        let speaker = PiperCommand.speakerArgument(voice: PiperVoiceCatalog.defaultVoice, speaker: 3)
        XCTAssertNil(speaker)
        XCTAssertEqual(PiperCommand.arguments(installation: installation, files: files, speaker: speaker, output: output), [
            "--quiet",
            "--model", "/Users/x/Library/Application Support/UniFi Camera Popup/Voices/de_DE-thorsten-medium/de_DE-thorsten-medium.onnx",
            "--config", "/Users/x/Library/Application Support/UniFi Camera Popup/Voices/de_DE-thorsten-medium/de_DE-thorsten-medium.onnx.json",
            "--espeak_data", "/Applications/UniFi Camera Popup.app/Contents/Resources/piper/espeak-ng-data",
            "--output_file", "/tmp/out.wav",
        ])
    }

    func testSpeakerOnlyForMultiSpeakerVoices() throws {
        let emotional = try XCTUnwrap(PiperVoiceCatalog.voice(id: "de_DE-thorsten_emotional-medium"))
        XCTAssertEqual(PiperCommand.speakerArgument(voice: emotional, speaker: 7), 7)
        XCTAssertEqual(PiperCommand.speakerArgument(voice: emotional, speaker: 8), 4)
        let files = PiperVoiceFiles(voice: emotional, folder: URL(fileURLWithPath: "/v"))
        let arguments = PiperCommand.arguments(installation: installation, files: files, speaker: 7, output: URL(fileURLWithPath: "/o.wav"))
        XCTAssertEqual(Array(arguments.suffix(2)), ["--speaker", "7"])
    }

    func testInputIsOneLine() {
        XCTAssertEqual(PiperCommand.input(for: "  Bin gleich da!\nEinen\tMoment,   bitte. "), "Bin gleich da! Einen Moment, bitte.\n")
        XCTAssertNil(PiperCommand.input(for: " \n\t "))
        XCTAssertNil(PiperCommand.input(for: ""))
    }

    func testLongInputIsCutAtAWord() throws {
        let text = String(repeating: "Hallo ", count: 400)
        let line = try XCTUnwrap(PiperCommand.input(for: text))
        XCTAssertLessThanOrEqual(line.count, PiperCommand.maxTextLength + 1)
        XCTAssertTrue(line.hasSuffix("Hallo\n"))
        let oneWord = try XCTUnwrap(PiperCommand.input(for: String(repeating: "a", count: 2_000)))
        XCTAssertEqual(oneWord.count, PiperCommand.maxTextLength + 1)
    }

    func testLengthLimitAndCounter() {
        let limit = String(repeating: "a", count: 1_000)
        XCTAssertFalse(PiperCommand.isTooLong("  \(limit)\n"))
        XCTAssertTrue(PiperCommand.isTooLong(limit + "b"))
        XCTAssertEqual(PiperCommand.lengthText(" Hallo "), "5 von höchstens 1000 Zeichen")
        XCTAssertEqual(PiperCommand.lengthText(limit), "1000 von höchstens 1000 Zeichen")
        XCTAssertEqual(PiperCommand.lengthText(String(repeating: "a", count: 3_000)),
                       "3000 Zeichen – höchstens 1000 Zeichen. Kürze den Text oder teile ihn auf zwei Ansagen auf.")
    }
}
