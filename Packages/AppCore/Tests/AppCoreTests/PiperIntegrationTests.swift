import AVFoundation
import XCTest
@testable import AppCore

/// The real Piper from piper/build/dist (piper/scripts/build-piper.sh) speaks with Thorsten (medium).
/// Skipped when the build is missing – never part of the app start.
final class PiperIntegrationTests: XCTestCase {
    private var dist: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("piper/build/dist", isDirectory: true)
    }

    func testBundledPiperSpeaksGerman() async throws {
        let installation = PiperInstallation(contents: dist)
        guard FileManager.default.isExecutableFile(atPath: installation.executable.path) else {
            throw XCTSkip("piper/build/dist fehlt – zuerst piper/scripts/build-piper.sh")
        }
        let files = PiperVoiceFiles(voice: PiperVoiceCatalog.bundled, folder: installation.bundledVoices)
        XCTAssertTrue(FileChecksum.matches(files.model, PiperVoiceCatalog.bundled.model))
        XCTAssertTrue(FileChecksum.matches(files.config, PiperVoiceCatalog.bundled.config))
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("piper-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: output) }
        let input = try XCTUnwrap(PiperCommand.input(for: "Achtung: An der Haustür hat jemand geklingelt.\nOkay, Computer-Update!"))
        let start = Date()
        try await PiperRunner.run(
            executable: installation.executable,
            arguments: PiperCommand.arguments(installation: installation, files: files, speaker: nil, output: output),
            input: input
        )
        XCTAssertLessThan(Date().timeIntervalSince(start), 10)
        let data = try Data(contentsOf: output)
        let info = try XCTUnwrap(WAVInfo.parse(data))
        XCTAssertEqual(info.sampleRate, 22_050)
        XCTAssertEqual(info.channels, 1)
        XCTAssertGreaterThan(info.duration, 2)
        XCTAssertTrue(WAVInfo.hasSpeech(data))
        // AVFoundation reads it like every other announcement, and the loudness step applies.
        let buffer = try AnnouncementAudio.load(output)
        XCTAssertEqual(Double(buffer.frameLength) / buffer.format.sampleRate, info.duration, accuracy: 0.01)
        XCTAssertLessThan(try AnnouncementAudio.loudnessGain(of: buffer), 1.0)
    }

    func testEmptyTextGivesNoSpeech() async throws {
        let installation = PiperInstallation(contents: dist)
        guard FileManager.default.isExecutableFile(atPath: installation.executable.path) else {
            throw XCTSkip("piper/build/dist fehlt – zuerst piper/scripts/build-piper.sh")
        }
        let files = PiperVoiceFiles(voice: PiperVoiceCatalog.bundled, folder: installation.bundledVoices)
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("piper-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: output) }
        try await PiperRunner.run(
            executable: installation.executable,
            arguments: PiperCommand.arguments(installation: installation, files: files, speaker: nil, output: output),
            input: "!!!\n"
        )
        XCTAssertFalse(WAVInfo.hasSpeech(try Data(contentsOf: output)))
    }
}
