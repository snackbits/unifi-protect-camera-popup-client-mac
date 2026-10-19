import XCTest
@testable import AppCore

final class TalkbackFramingTests: XCTestCase {
    func testADTSHeaderBytes() throws {
        // 48 kHz (index 3), mono, 100 bytes payload → frame length 107.
        let header = try XCTUnwrap(ADTS.header(payloadLength: 100, sampleRate: 48_000))
        XCTAssertEqual([UInt8](header), [0xFF, 0xF1, 0x4C, 0x40, 0x0D, 0x7F, 0xFC])
        // 22 050 Hz (index 7), 300 bytes → 307 = 0b1_0011_0011.
        let other = try XCTUnwrap(ADTS.header(payloadLength: 300, sampleRate: 22_050))
        XCTAssertEqual([UInt8](other), [0xFF, 0xF1, 0x5C, 0x40, 0x26, 0x7F, 0xFC])
    }

    func testADTSRejectsUnsupportedInput() {
        XCTAssertNil(ADTS.header(payloadLength: 10, sampleRate: 44_000))
        XCTAssertNil(ADTS.header(payloadLength: 8_185, sampleRate: 48_000))
        XCTAssertNil(ADTS.header(payloadLength: -1, sampleRate: 48_000))
        XCTAssertNotNil(ADTS.header(payloadLength: 8_184, sampleRate: 48_000))
        XCTAssertEqual(ADTS.frame(Data([1, 2, 3]), sampleRate: 16_000)?.count, 10)
    }

    func testRTPHeaderLayout() {
        var rtp = RTPPacketizer(sequenceNumber: 0x1234, timestamp: 0x0102_0304, ssrc: 0xA1B2_C3D4)
        let packet = rtp.packet(payload: Data([0xAA, 0xBB]), timestampIncrement: 960)
        XCTAssertEqual([UInt8](packet), [0x80, 0xE1, 0x12, 0x34, 0x01, 0x02, 0x03, 0x04, 0xA1, 0xB2, 0xC3, 0xD4, 0xAA, 0xBB])
        XCTAssertEqual(rtp.sequenceNumber, 0x1235)
        XCTAssertEqual(rtp.timestamp, 0x0102_0304 + 960)
    }

    func testRTPWrapsSequenceAndTimestamp() {
        var rtp = RTPPacketizer(sequenceNumber: .max, timestamp: .max - 100, ssrc: 1)
        _ = rtp.packet(payload: Data(), timestampIncrement: 960)
        XCTAssertEqual(rtp.sequenceNumber, 0)
        XCTAssertEqual(rtp.timestamp, 859)
    }

    func testOpusTimestampUses48kClock() {
        XCTAssertEqual(RTPPacketizer.timestampIncrement(frames: 960, sampleRate: 48_000), 960)
        XCTAssertEqual(RTPPacketizer.timestampIncrement(frames: 320, sampleRate: 16_000), 960)
    }

    func testPacerKeepsAbsoluteSchedule() {
        var pacer = RealtimePacer(sampleRate: 48_000)
        XCTAssertEqual(pacer.sendTime(forSamples: 960, now: 100), 100, accuracy: 1e-9)
        XCTAssertEqual(pacer.sendTime(forSamples: 960, now: 100), 100.02, accuracy: 1e-9)
        XCTAssertEqual(pacer.sendTime(forSamples: 960, now: 100.001), 100.04, accuracy: 1e-9)
        // Slightly late: send now, keep the schedule.
        XCTAssertEqual(pacer.sendTime(forSamples: 960, now: 100.1), 100.1, accuracy: 1e-9)
        XCTAssertEqual(pacer.sendTime(forSamples: 960, now: 100.1), 100.1, accuracy: 1e-9)
    }

    func testPacerReanchorsAfterStall() {
        var pacer = RealtimePacer(sampleRate: 48_000, maxLag: 0.25)
        _ = pacer.sendTime(forSamples: 960, now: 0)
        // Source stalled for a second: no burst afterwards.
        XCTAssertEqual(pacer.sendTime(forSamples: 960, now: 1.0), 1.0, accuracy: 1e-9)
        XCTAssertEqual(pacer.sendTime(forSamples: 960, now: 1.0), 1.02, accuracy: 1e-9)
    }

    func testTargetValidation() throws {
        let aac = try TalkbackTarget.make(host: " 192.168.1.20 ", port: 7004, codecName: "AAC", sampleRate: 0)
        XCTAssertEqual(aac, TalkbackTarget(host: "192.168.1.20", port: 7004, codec: .aac, sampleRate: 22_050))
        let opus = try TalkbackTarget.make(host: "cam", port: 7004, codecName: "libopus", sampleRate: 16_000)
        XCTAssertEqual(opus.codec, .opus)
        XCTAssertEqual(opus.sampleRate, 16_000)
        XCTAssertThrowsError(try TalkbackTarget.make(host: "cam", port: 7004, codecName: "vorbis", sampleRate: 48_000)) {
            XCTAssertEqual($0 as? TalkbackError, .unsupportedCodec("vorbis"))
        }
        XCTAssertThrowsError(try TalkbackTarget.make(host: "cam", port: 7004, codecName: "", sampleRate: 48_000)) {
            XCTAssertEqual($0 as? TalkbackError, .unsupportedCodec("unbekannt"))
        }
        XCTAssertThrowsError(try TalkbackTarget.make(host: "", port: 7004, codecName: "opus", sampleRate: 48_000)) {
            XCTAssertEqual($0 as? TalkbackError, .invalidAddress("leer"))
        }
        XCTAssertThrowsError(try TalkbackTarget.make(host: "cam", port: 7004, codecName: "opus", sampleRate: 44_100)) {
            XCTAssertEqual($0 as? TalkbackError, .unsupportedSampleRate(44_100))
        }
    }
}
