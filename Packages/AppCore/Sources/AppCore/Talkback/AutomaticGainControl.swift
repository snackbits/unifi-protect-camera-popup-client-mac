import Foundation

/// Level control between resampler and encoder (16-bit mono at the camera rate).
///
/// `adaptive` (microphone): brings speech to −20 dBFS RMS like the announcements – at most +18 dB,
/// at least −12 dB; the gain falls at once and rises by at most 12 dB/s; blocks below −50 dBFS
/// (pauses, room noise) leave it unchanged. Always: `outputGain` (the user's volume) on top and a
/// fast peak limit at −1 dBFS, in 10 ms blocks. Not thread-safe: use from one queue.
public final class AutomaticGainControl {
    public static let targetDBFS: Float = Loudness.targetDBFS
    public static let maxGainDB: Float = 18
    public static let minGainDB: Float = -12
    public static let gateDBFS: Float = -50
    public static let riseDBPerSecond: Float = 12
    public static let ceiling: Float = Loudness.linear(Loudness.ceilingDBFS) * 32_767

    public let sampleRate: Int
    public let outputGain: Float
    public let adaptive: Bool
    /// Current automatic gain in dB (0 when not adaptive).
    public private(set) var gainDB: Float = 0
    private var applied: Float

    public init(sampleRate: Int, outputGain: Float = 1, adaptive: Bool = true) {
        self.sampleRate = max(sampleRate, 1)
        self.outputGain = max(0, outputGain.isFinite ? outputGain : 1)
        self.adaptive = adaptive
        applied = self.outputGain
    }

    public func process(_ samples: [Int16]) -> [Int16] {
        guard !samples.isEmpty else { return [] }
        let block = max(1, sampleRate / 100)
        var output: [Int16] = []
        output.reserveCapacity(samples.count)
        var start = 0
        while start < samples.count {
            let end = min(start + block, samples.count)
            processBlock(samples[start..<end], into: &output)
            start = end
        }
        return output
    }

    private func processBlock(_ chunk: ArraySlice<Int16>, into output: inout [Int16]) {
        var sumSquares: Double = 0
        var peak: Float = 0
        for sample in chunk {
            let value = Float(sample)
            sumSquares += Double(value) * Double(value)
            peak = max(peak, abs(value))
        }
        if adaptive {
            let level = Loudness.dB(Float((sumSquares / Double(chunk.count)).squareRoot()) / 32_768)
            if level > Self.gateDBFS {
                let desired = min(Self.maxGainDB, max(Self.minGainDB, Self.targetDBFS - level))
                if desired < gainDB {
                    gainDB = desired
                } else {
                    let step = Self.riseDBPerSecond * Float(chunk.count) / Float(sampleRate)
                    gainDB = min(desired, gainDB + step)
                }
            }
        }
        var target = Loudness.linear(gainDB) * outputGain
        if peak > 0, peak * target > Self.ceiling {
            target = Self.ceiling / peak
        }
        // Falling: at once (no peak slips through). Rising: ramp across the block (no click).
        let from = target < applied ? target : applied
        let count = Float(chunk.count)
        for (offset, sample) in chunk.enumerated() {
            let gain = from + (target - from) * Float(offset + 1) / count
            let scaled = (Float(sample) * gain).rounded()
            output.append(Int16(max(-32_768, min(32_767, scaled))))
        }
        applied = target
    }
}
