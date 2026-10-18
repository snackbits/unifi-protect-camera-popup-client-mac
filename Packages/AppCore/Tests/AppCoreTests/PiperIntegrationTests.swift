import AVFoundation
import XCTest
@testable import AppCore

/// The real Piper from piper/build/dist (piper/scripts/build-piper.sh) speaks with Thorsten (medium)
/// from piper/.cache (scripts/fetch.sh – no voice is bundled). Skipped when either is missing –
/// never part of the app start.
final class PiperIntegrationTests: XCTestCase {
    private var piper: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("piper", isDirectory: true)
    }
    private var dist: URL { piper.appendingPathComponent("build/dist", isDirectory: true) }
    private var voiceFiles: PiperVoiceFiles {
        PiperVoiceFiles(voice: PiperVoiceCatalog.defaultVoice, folder: piper.appendingPathComponent(".cache", isDirectory: true))
    }

    private func requireBuild(_ installation: PiperInstallation) throws {
        guard FileManager.default.isExecutableFile(atPath: installation.executable.path),
              FileManager.default.fileExists(atPath: voiceFiles.model.path) else {
            throw XCTSkip("piper/build/dist oder piper/.cache fehlt – zuerst piper/scripts/build-piper.sh")
        }
    }

    func testBundledPiperSpeaksGerman() async throws {
        let installation = PiperInstallation(contents: dist)
        try requireBuild(installation)
        let files = voiceFiles
        XCTAssertTrue(FileChecksum.matches(files.model, PiperVoiceCatalog.defaultVoice.model))
        XCTAssertTrue(FileChecksum.matches(files.config, PiperVoiceCatalog.defaultVoice.config))
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
        try requireBuild(installation)
        let files = voiceFiles
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
