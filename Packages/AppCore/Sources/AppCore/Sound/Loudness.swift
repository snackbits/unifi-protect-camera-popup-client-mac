import Foundation

/// One loudness for every announcement (Phase 5): −20 dBFS RMS, peaks at most −1 dBFS.
/// The microphone (`AutomaticGainControl`) aims at the same level, so talking and
/// announcements arrive equally loud at the camera.
public enum Loudness {
    public static let targetDBFS: Float = -20
    public static let ceilingDBFS: Float = -1
    /// Blocks quieter than this are pauses and do not count (no boosting of breaks).
    public static let gateDBFS: Float = -50
    public static let maxBoostDB: Float = 18
    public static let maxCutDB: Float = -30
    /// Measuring block (50 ms).
    public static let blockSeconds = 0.05

    public static func dB(_ linear: Float) -> Float {
        linear > 0 ? 20 * log10(linear) : -120
    }

    public static func linear(_ dB: Float) -> Float {
        pow(10, dB / 20)
    }

    /// RMS of the blocks above `gateDBFS` (samples −1…1, mono); nil = silence only.
    public static func gatedRMSdB(_ samples: [Float], sampleRate: Double) -> Float? {
        let block = max(1, Int(sampleRate * blockSeconds))
        var sum: Double = 0
        var counted = 0
        var start = 0
        while start < samples.count {
            let end = min(start + block, samples.count)
            var blockSum: Double = 0
            for index in start..<end {
                let value = Double(samples[index])
                blockSum += value * value
            }
            let rms = Float((blockSum / Double(end - start)).squareRoot())
            if dB(rms) > gateDBFS {
                sum += blockSum
                counted += end - start
            }
            start = end
        }
        guard counted > 0 else { return nil }
        return dB(Float((sum / Double(counted)).squareRoot()))
    }

    public static func peakDB(_ samples: [Float]) -> Float {
        dB(samples.reduce(0) { max($0, abs($1)) })
    }

    /// Factor that brings the samples to −20 dBFS RMS without peaks above −1 dBFS
    /// (between −30 and +18 dB). Silence keeps 1.
    public static func normalizationGain(_ samples: [Float], sampleRate: Double) -> Float {
        guard let rms = gatedRMSdB(samples, sampleRate: sampleRate) else { return 1 }
        let byLevel = targetDBFS - rms
        let byPeak = ceilingDBFS - peakDB(samples)
        return linear(min(maxBoostDB, max(maxCutDB, min(byLevel, byPeak))))
    }
}
