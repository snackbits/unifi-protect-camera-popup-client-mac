import XCTest
@testable import AppCore

final class AutomaticGainControlTests: XCTestCase {
    private let rate = 16_000

    /// Sine with the given RMS level in dBFS.
    private func tone(dBFS: Float, seconds: Double) -> [Int16] {
        let amplitude = Double(Loudness.linear(dBFS)) * 32_768 * 2.0.squareRoot()
        return (0..<Int(seconds * Double(rate))).map {
            Int16(max(-32_768, min(32_767, amplitude * sin(2 * .pi * 440 * Double($0) / Double(rate)))))
        }
    }

    private func rmsDB(_ samples: ArraySlice<Int16>) -> Float {
        let sum = samples.reduce(0.0) { $0 + Double($1) * Double($1) }
        return Loudness.dB(Float((sum / Double(samples.count)).squareRoot()) / 32_768)
    }

    /// Feeds in microphone-sized chunks (1024 frames).
    private func run(_ agc: AutomaticGainControl, _ input: [Int16]) -> [Int16] {
        stride(from: 0, to: input.count, by: 1_024).flatMap {
            agc.process(Array(input[$0..<min($0 + 1_024, input.count)]))
        }
    }

    func testQuietSpeechIsRaisedToTarget() {
        let output = run(AutomaticGainControl(sampleRate: rate), tone(dBFS: -30, seconds: 3))
        XCTAssertEqual(rmsDB(output.suffix(rate)), -20, accuracy: 1)
    }

    func testBoostStopsAt18dB() {
        let output = run(AutomaticGainControl(sampleRate: rate), tone(dBFS: -45, seconds: 3))
        XCTAssertEqual(rmsDB(output.suffix(rate)), -27, accuracy: 1)
    }

    func testNoiseIsNotBoosted() {
        let agc = AutomaticGainControl(sampleRate: rate)
        let noise = tone(dBFS: -70, seconds: 2)
        let output = run(agc, noise)
        XCTAssertEqual(agc.gainDB, 0)
        XCTAssertEqual(rmsDB(output[...]), rmsDB(noise[...]), accuracy: 0.1)
    }

    func testBurstAfterQuietNeverExceedsCeiling() {
        let agc = AutomaticGainControl(sampleRate: rate, outputGain: 1.5)
        let quiet = run(agc, tone(dBFS: -45, seconds: 2))
        XCTAssertGreaterThan(agc.gainDB, 15)
        let burst = run(agc, tone(dBFS: -3, seconds: 0.5))
        let peak = burst.map { abs(Int32($0)) }.max() ?? 0
        XCTAssertLessThanOrEqual(Float(peak), AutomaticGainControl.ceiling + 1)
        XCTAssertFalse(quiet.isEmpty)
    }

    func testUserVolumeOnTop() {
        let output = run(AutomaticGainControl(sampleRate: rate, outputGain: 1.5), tone(dBFS: -20, seconds: 2))
        XCTAssertEqual(rmsDB(output.suffix(rate)), -20 + Loudness.dB(1.5), accuracy: 0.5)
    }

    func testFixedGainOnlyLimits() {
        // Announcements: no automatic gain, just volume and the −1 dBFS ceiling.
        let agc = AutomaticGainControl(sampleRate: rate, outputGain: 1.5, adaptive: false)
        let quiet = tone(dBFS: -30, seconds: 1)
        XCTAssertEqual(rmsDB(run(agc, quiet).suffix(rate / 2)), -30 + Loudness.dB(1.5), accuracy: 0.3)
        let loud = run(agc, tone(dBFS: -4, seconds: 1))
        XCTAssertLessThanOrEqual(Float(loud.map { abs(Int32($0)) }.max() ?? 0), AutomaticGainControl.ceiling + 1)
        XCTAssertEqual(agc.gainDB, 0)
    }

    func testEmptyInput() {
        XCTAssertTrue(AutomaticGainControl(sampleRate: rate).process([]).isEmpty)
    }
}
