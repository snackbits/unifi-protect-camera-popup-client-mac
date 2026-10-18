import AVFoundation
import XCTest
@testable import AppCore

final class SoundSettingsTests: XCTestCase {
    func testDefaultsShipBothRecordings() {
        let settings = SoundSettings()
        XCTAssertEqual(settings.announcements.map(\.name), ["Bin gleich da", "Paket bitte abstellen"])
        XCTAssertEqual(settings.announcements.map(\.badge), ["KI-STIMME", "KI-STIMME"])
        XCTAssertEqual(settings.announcements.map(\.menuTag), ["KI-Stimme", "KI-Stimme"])
        XCTAssertTrue(settings.announcements.allSatisfy(\.usesBundledRecording))
        XCTAssertEqual(settings.talkMode, .hold)
        XCTAssertEqual(settings.talkGain, 1, accuracy: 0.0001)
        XCTAssertEqual(settings.announcementGain, 1, accuracy: 0.0001)
    }

    func testLenientDecoding() throws {
        let json = #"{"announcements":[{"broken":true},{"id":"6F0C6A52-4C4B-4E58-9B1E-2F3C1C0A0009","name":"Gong","kind":"file","text":"","fileName":"gong.mp3","duration":2}],"talkMode":"shout","cameraVolume":7}"#
        let settings = try JSONDecoder().decode(SoundSettings.self, from: Data(json.utf8))
        XCTAssertEqual(settings.announcements.map(\.name), ["Gong"])
        XCTAssertEqual(settings.talkMode, .hold)
        XCTAssertEqual(settings.talkVolume, 1)
        XCTAssertEqual(settings.announcementVolume, 1)
        XCTAssertEqual(settings.referencedFiles, ["gong.mp3"])
        let empty = try JSONDecoder().decode(SoundSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(empty, SoundSettings())
    }

    func testOldSingleVolumeGoesIntoBoth() throws {
        let old = try JSONDecoder().decode(SoundSettings.self, from: Data(#"{"talkMode":"toggle","cameraVolume":0.4}"#.utf8))
        XCTAssertEqual(old.talkVolume, 0.4)
        XCTAssertEqual(old.announcementVolume, 0.4)
        var changed = old
        changed.talkVolume = 0.9
        let json = String(decoding: try JSONEncoder().encode(changed), as: UTF8.self)
        XCTAssertFalse(json.contains("cameraVolume"))
        let again = try JSONDecoder().decode(SoundSettings.self, from: Data(json.utf8))
        XCTAssertEqual(again.talkVolume, 0.9)
        XCTAssertEqual(again.announcementVolume, 0.4)
    }

    func testLoudnessGainIsLenient() throws {
        let json = #"{"id":"6F0C6A52-4C4B-4E58-9B1E-2F3C1C0A0009","name":"Gong","kind":"file","loudnessGain":"laut"}"#
        XCTAssertNil(try JSONDecoder().decode(Announcement.self, from: Data(json.utf8)).loudnessGain)
        let measured = Announcement(name: "Gong", kind: .file, loudnessGain: 0.5)
        XCTAssertEqual(try JSONDecoder().decode(Announcement.self, from: JSONEncoder().encode(measured)).loudnessGain, 0.5)
        XCTAssertNil(Announcement(name: "x", kind: .file, loudnessGain: .infinity).loudnessGain)
    }

    func testRoundTripAndEditing() throws {
        var settings = SoundSettings()
        let gong = Announcement(name: "Gong", kind: .file, fileName: "a.mp3", duration: 2.2)
        settings.add(gong)
        var edited = gong
        edited.name = "Gong 2"
        settings.update(edited)
        XCTAssertEqual(settings.announcement(id: gong.id)?.name, "Gong 2")
        let again = try JSONDecoder().decode(SoundSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(again, settings)
        XCTAssertEqual(settings.remove(id: gong.id)?.fileName, "a.mp3")
        XCTAssertNil(settings.remove(id: gong.id))
    }

    func testLengthText() {
        XCTAssertEqual(Announcement.lengthText(2.74), "0:03")
        XCTAssertEqual(Announcement.lengthText(0.2), "0:01")
        XCTAssertEqual(Announcement.lengthText(65), "1:05")
        XCTAssertEqual(Announcement.lengthText(0), "–:–")
        XCTAssertEqual(Announcement.lengthText(.nan), "–:–")
    }

    func testSuggestedNames() {
        XCTAssertEqual(Announcement.suggestedName(forText: "Bin gleich da! Einen kleinen Moment, bitte."), "Bin gleich da")
        XCTAssertEqual(Announcement.suggestedName(forText: "   "), "Neue Ansage")
        XCTAssertEqual(Announcement.suggestedName(forText: "!!!"), "Neue Ansage")
        XCTAssertEqual(Announcement.suggestedName(forText: String(repeating: "a", count: 40)).count, 32)
        XCTAssertEqual(Announcement.suggestedName(forFile: URL(fileURLWithPath: "/tmp/Gong laut.mp3")), "Gong laut")
    }

    func testBundledVoiceOnlyForBundledWording() {
        let original = SoundSettings.bundledBinGleichDa
        XCTAssertTrue(SoundSettings.offersBundledVoice(for: original, text: " Bin gleich da! Einen kleinen Moment, bitte. "))
        XCTAssertFalse(SoundSettings.offersBundledVoice(for: original, text: "Bin gleich da."))
        var rerendered = original
        rerendered.fileName = "x.caf"
        rerendered.voiceIdentifier = "com.apple.voice.premium.de-DE.Anna"
        XCTAssertFalse(rerendered.usesBundledRecording)
        XCTAssertEqual(SoundSettings.bundledOriginal(for: rerendered), original)
        XCTAssertFalse(SoundSettings.offersBundledVoice(for: Announcement(name: "Gong", kind: .file), text: ""))
    }

    func testAutomaticNames() {
        XCTAssertTrue(Announcement(name: "Neue Ansage", kind: .speech).hasAutomaticName)
        XCTAssertTrue(SoundSettings.bundledBinGleichDa.hasAutomaticName)
        XCTAssertFalse(Announcement(name: "Paketbote", kind: .speech, text: "Bitte vor die Tür legen.").hasAutomaticName)
        XCTAssertFalse(Announcement(name: "Gong", kind: .file).hasAutomaticName)
    }

    func testStandardizedConvertsInt16() throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 22_050, channels: 1, interleaved: true)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 100)!
        buffer.frameLength = 100
        buffer.int16ChannelData![0][10] = 16_384
        let float = try AnnouncementAudio.standardized(buffer)
        XCTAssertEqual(float.format.commonFormat, .pcmFormatFloat32)
        XCTAssertEqual(float.frameLength, 100)
        XCTAssertEqual(float.floatChannelData![0][10], 0.5, accuracy: 0.001)
    }

    func testSpeechRendersIntoBuffer() async throws {
        guard let voice = AnnouncementAudio.voices().first else { throw XCTSkip("Keine deutsche macOS-Stimme installiert") }
        XCTAssertTrue(AnnouncementAudio.label(for: voice).hasSuffix(" · macOS"))
        let buffer = try await AnnouncementAudio.render(text: "Bin gleich da.", voiceIdentifier: voice.identifier)
        XCTAssertGreaterThan(Double(buffer.frameLength) / buffer.format.sampleRate, 0.3)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("speech-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        try AnnouncementAudio.write(buffer, to: url)
        XCTAssertEqual(try AnnouncementAudio.duration(of: url), Double(buffer.frameLength) / buffer.format.sampleRate, accuracy: 0.05)
        XCTAssertEqual(Double(try AnnouncementAudio.load(url).frameLength), Double(buffer.frameLength), accuracy: Double(buffer.frameLength) * 0.02)
    }

    func testRenderRejectsEmptyText() async {
        do {
            _ = try await AnnouncementAudio.render(text: "   ", voiceIdentifier: nil)
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? TalkbackError, .speechFailed)
        }
    }

    func testRenderTimesOut() async throws {
        do {
            _ = try await AnnouncementAudio.render(text: "Bin gleich da, ich muss noch etwas Längeres sagen.", voiceIdentifier: nil, timeout: 0.001)
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? TalkbackError, .speechFailed)
        }
    }

    func testAnnouncementDecodingKeepsEntryAndSanitizesFileName() throws {
        let json = #"{"id":"6F0C6A52-4C4B-4E58-9B1E-2F3C1C0A0009","name":"X","kind":"file","fileName":"../../etc/passwd"}"#
        let entry = try JSONDecoder().decode(Announcement.self, from: Data(json.utf8))
        XCTAssertEqual(entry.fileName, "passwd")
        XCTAssertEqual(entry.text, "")
        XCTAssertEqual(entry.duration, 0)
        for bad in ["..", ".", "", "a/.."] {
            let j = #"{"id":"6F0C6A52-4C4B-4E58-9B1E-2F3C1C0A0009","name":"X","kind":"file","fileName":"\#(bad)"}"#
            XCTAssertNil(try JSONDecoder().decode(Announcement.self, from: Data(j.utf8)).fileName, bad)
        }
    }
}
