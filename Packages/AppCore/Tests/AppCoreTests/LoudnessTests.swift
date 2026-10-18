import AVFoundation
import XCTest
@testable import AppCore

final class LoudnessTests: XCTestCase {
    private func sine(_ amplitude: Float, seconds: Double, rate: Double = 16_000) -> [Float] {
        (0..<Int(seconds * rate)).map { amplitude * Float(sin(2 * .pi * 440 * Double($0) / rate)) }
    }

    func testPausesDoNotCount() throws {
        // Sine 0.1 = −23 dBFS RMS; one second of silence after it changes nothing.
        let speech = sine(0.1, seconds: 1) + [Float](repeating: 0, count: 16_000)
        let rms = try XCTUnwrap(Loudness.gatedRMSdB(speech, sampleRate: 16_000))
        XCTAssertEqual(rms, -23.0, accuracy: 0.2)
        XCTAssertEqual(Loudness.dB(Loudness.normalizationGain(speech, sampleRate: 16_000)), 3.0, accuracy: 0.2)
    }

    func testLoudFileIsTurnedDown() {
        let loud = sine(0.9, seconds: 1)
        XCTAssertEqual(Loudness.dB(Loudness.normalizationGain(loud, sampleRate: 16_000)), -16.1, accuracy: 0.2)
    }

    func testSpikeLimitsGain() {
        // Quiet speech (−29 dBFS) with one click near full scale: the peak, not the level, decides.
        var samples = sine(0.05, seconds: 1)
        samples[8_000] = 0.9
        let gain = Loudness.dB(Loudness.normalizationGain(samples, sampleRate: 16_000))
        XCTAssertEqual(gain, -1 - Loudness.dB(0.9), accuracy: 0.05)
        XCTAssertLessThanOrEqual(0.9 * Loudness.linear(gain), Loudness.linear(-1) + 0.0001)
    }

    func testBoostIsCapped() {
        let quiet = sine(0.01, seconds: 1) // −43 dBFS
        XCTAssertEqual(Loudness.dB(Loudness.normalizationGain(quiet, sampleRate: 16_000)), 18, accuracy: 0.01)
    }

    func testSilentFileKeepsGain() {
        XCTAssertEqual(Loudness.normalizationGain([Float](repeating: 0, count: 16_000), sampleRate: 16_000), 1)
        XCTAssertEqual(Loudness.normalizationGain([], sampleRate: 16_000), 1)
        // Only hiss below the gate: not boosted.
        XCTAssertEqual(Loudness.normalizationGain(sine(0.001, seconds: 1), sampleRate: 16_000), 1)
    }

    func testBufferMeasurementAveragesChannels() throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000)!
        buffer.frameLength = 16_000
        let tone = sine(0.1, seconds: 1)
        for index in 0..<16_000 {
            buffer.floatChannelData![0][index] = tone[index]
            buffer.floatChannelData![1][index] = tone[index]
        }
        XCTAssertEqual(try AnnouncementAudio.monoSamples(buffer).count, 16_000)
        XCTAssertEqual(Loudness.dB(try AnnouncementAudio.loudnessGain(of: buffer)), 3.0, accuracy: 0.2)
    }
}
