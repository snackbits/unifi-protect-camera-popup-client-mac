import XCTest
@testable import AppCore

final class WAVFileTests: XCTestCase {
    /// 16-bit PCM WAV as Piper writes it (44-byte header), optionally with a LIST chunk before data.
    static func wav(samples: [Int16], rate: Int = 22_050, channels: Int = 1, list: Bool = false, bits: Int = 16, format: Int = 1) -> Data {
        func u16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)] }
        func u32(_ v: Int) -> [UInt8] { u16(v & 0xFFFF) + u16(v >> 16 & 0xFFFF) }
        let body = samples.flatMap { u16(Int(UInt16(bitPattern: $0))) }
        let listChunk: [UInt8] = list ? Array("LIST".utf8) + u32(5) + Array("INFOx".utf8) + [0] : []
        var bytes = Array("WAVE".utf8)
        bytes += Array("fmt ".utf8) + u32(16) + u16(format) + u16(channels) + u32(rate)
        bytes += u32(rate * channels * bits / 8) + u16(channels * bits / 8) + u16(bits)
        bytes += listChunk + Array("data".utf8) + u32(body.count) + body
        return Data(Array("RIFF".utf8) + u32(bytes.count) + bytes)
    }

    func testParsesPiperHeader() throws {
        let info = try XCTUnwrap(WAVInfo.parse(Self.wav(samples: [Int16](repeating: 0, count: 22_050))))
        XCTAssertEqual(info.channels, 1)
        XCTAssertEqual(info.sampleRate, 22_050)
        XCTAssertEqual(info.bitsPerSample, 16)
        XCTAssertEqual(info.dataOffset, 44)
        XCTAssertEqual(info.duration, 1.0, accuracy: 0.0001)
    }

    func testSkipsOtherChunksAndOddPadding() throws {
        let info = try XCTUnwrap(WAVInfo.parse(Self.wav(samples: [1, 2, 3], rate: 16_000, list: true)))
        XCTAssertEqual(info.dataOffset, 44 + 14)
        XCTAssertEqual(info.dataLength, 6)
    }

    func testRejectsWhatIsNotPiperOutput() {
        XCTAssertNil(WAVInfo.parse(Data()))
        XCTAssertNil(WAVInfo.parse(Data("RIFF....WAVE".utf8)))
        XCTAssertNil(WAVInfo.parse(Data("ID3 not a wav file at all".utf8)))
        XCTAssertNil(WAVInfo.parse(Self.wav(samples: [0], bits: 8)))
        XCTAssertNil(WAVInfo.parse(Self.wav(samples: [0], format: 3)))
    }

    func testTruncatedDataIsClamped() throws {
        let full = Self.wav(samples: [Int16](repeating: 100, count: 1_000))
        let info = try XCTUnwrap(WAVInfo.parse(full.prefix(44 + 500)))
        XCTAssertEqual(info.dataLength, 500)
    }

    func testSilenceIsNoSpeech() {
        // Empty text: Piper writes 0.2 s of zeros.
        XCTAssertFalse(WAVInfo.hasSpeech(Self.wav(samples: [Int16](repeating: 0, count: 4_410))))
        let tone = (0..<22_050).map { Int16(8_000 * sin(2 * Double.pi * 220 * Double($0) / 22_050)) }
        XCTAssertTrue(WAVInfo.hasSpeech(Self.wav(samples: tone)))
        XCTAssertFalse(WAVInfo.hasSpeech(Data("garbage".utf8)))
    }

    func testStereoIsAveraged() throws {
        let data = Self.wav(samples: [16_384, -16_384, 16_384, 16_384], channels: 2)
        let info = try XCTUnwrap(WAVInfo.parse(data))
        XCTAssertEqual(WAVInfo.monoSamples(data, info: info), [0, 0.5])
    }
}
