import AVFoundation
import XCTest
@testable import AppCore

final class TalkbackEncoderTests: XCTestCase {
    static func sine(seconds: Double, rate: Int, frequency: Double = 440) -> [Int16] {
        (0..<Int(seconds * Double(rate))).map { index in
            Int16(12_000 * sin(2 * .pi * frequency * Double(index) / Double(rate)))
        }
    }

    func testOpusMakes20msPackets() throws {
        let encoder = try TalkbackEncoder(codec: .opus, sampleRate: 48_000)
        XCTAssertEqual(encoder.framesPerPacket, 960)
        var packets: [EncodedPacket] = []
        // Fed in uneven chunks like a microphone tap.
        let samples = Self.sine(seconds: 1, rate: 48_000)
        for start in stride(from: 0, to: samples.count, by: 1_234) {
            packets += try encoder.encode(Array(samples[start..<min(start + 1_234, samples.count)]))
        }
        XCTAssertGreaterThanOrEqual(packets.count, 48)
        XCTAssertLessThanOrEqual(packets.count, 50)
        XCTAssertTrue(packets.allSatisfy { !$0.data.isEmpty && $0.data.count < 1_400 && $0.frames == 960 })
    }

    func testAACProducesDecodableADTS() throws {
        let rate = 22_050
        let encoder = try TalkbackEncoder(codec: .aac, sampleRate: rate)
        XCTAssertEqual(encoder.framesPerPacket, 1_024)
        let packets = try encoder.encode(Self.sine(seconds: 1, rate: rate))
        XCTAssertGreaterThanOrEqual(packets.count, 18)
        var stream = Data()
        for packet in packets {
            stream.append(try XCTUnwrap(ADTS.frame(packet.data, sampleRate: rate)))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("talkback-\(UUID().uuidString).aac")
        defer { try? FileManager.default.removeItem(at: url) }
        try stream.write(to: url)
        let file = try AVAudioFile(forReading: url)
        XCTAssertEqual(file.fileFormat.sampleRate, Double(rate))
        XCTAssertEqual(file.fileFormat.channelCount, 1)
        XCTAssertGreaterThan(Double(file.length) / Double(rate), 0.7)
    }

    func testRejectsVorbisAndOddRates() {
        XCTAssertThrowsError(try TalkbackEncoder(codec: .vorbis, sampleRate: 48_000))
        XCTAssertThrowsError(try TalkbackEncoder(codec: .opus, sampleRate: 44_100))
        XCTAssertThrowsError(try TalkbackEncoder(codec: .aac, sampleRate: 7_000))
    }

    func testResamplerDownmixesAndAppliesGain() throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_800)!
        buffer.frameLength = 4_800
        for channel in 0..<2 {
            for index in 0..<4_800 { buffer.floatChannelData![channel][index] = 0.9 }
        }
        let loud = try PCMResampler(sampleRate: 16_000, gain: 1.5).convert(buffer)
        // The sample-rate converter keeps a little back for the next buffer.
        XCTAssertGreaterThan(loud.count, 1_200)
        XCTAssertLessThanOrEqual(loud.count, 1_600)
        // 0.9 × 1.5 clips at full scale instead of wrapping around.
        XCTAssertEqual(loud[800], 32_767)
        XCTAssertEqual(PCMResampler(sampleRate: 16_000).silence(seconds: 0.3).count, 4_800)
    }
}
