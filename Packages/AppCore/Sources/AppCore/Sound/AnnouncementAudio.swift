import AVFoundation
import Foundation

/// Loads, converts, measures and writes announcement audio (MP3, CAF, Piper WAV).
public enum AnnouncementAudio {
    /// Whole file as one PCM buffer in its processing format.
    public static func load(_ url: URL) throws -> AVAudioPCMBuffer {
        let file: AVAudioFile
        do { file = try AVAudioFile(forReading: url) } catch {
            throw TalkbackError.audioFile(error.localizedDescription)
        }
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames) else {
            throw TalkbackError.audioFile("leer")
        }
        do { try file.read(into: buffer) } catch {
            throw TalkbackError.audioFile(error.localizedDescription)
        }
        return buffer
    }

    public static func duration(of url: URL) throws -> TimeInterval {
        do {
            let file = try AVAudioFile(forReading: url)
            return Double(file.length) / file.processingFormat.sampleRate
        } catch {
            throw TalkbackError.audioFile(error.localizedDescription)
        }
    }

    /// Same audio as 32-bit float, non-interleaved (what AVAudioPlayerNode and the mixer accept).
    public static func standardized(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        let format = buffer.format
        if format.commonFormat == .pcmFormatFloat32, !format.isInterleaved { return buffer }
        guard let target = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: format.channelCount),
              let converter = AVAudioConverter(from: format, to: target),
              let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: max(buffer.frameLength, 1)) else {
            throw TalkbackError.audioFile("Format")
        }
        do { try converter.convert(to: output, from: buffer) } catch {
            throw TalkbackError.audioFile(error.localizedDescription)
        }
        return output
    }

    /// All channels averaged to one float channel (−1…1).
    public static func monoSamples(_ buffer: AVAudioPCMBuffer) throws -> [Float] {
        let float = try standardized(buffer)
        guard let channels = float.floatChannelData else { return [] }
        let count = Int(float.frameLength)
        let channelCount = Int(float.format.channelCount)
        guard count > 0, channelCount > 0 else { return [] }
        var mono = [Float](repeating: 0, count: count)
        for channel in 0..<channelCount {
            let data = channels[channel]
            for index in 0..<count { mono[index] += data[index] }
        }
        if channelCount > 1 {
            let scale = 1 / Float(channelCount)
            for index in 0..<count { mono[index] *= scale }
        }
        return mono
    }

    /// Factor for one loudness across all announcements (see `Loudness`).
    public static func loudnessGain(of buffer: AVAudioPCMBuffer) throws -> Float {
        Loudness.normalizationGain(try monoSamples(buffer), sampleRate: buffer.format.sampleRate)
    }

    /// Writes a buffer as CAF.
    public static func write(_ buffer: AVAudioPCMBuffer, to url: URL) throws {
        do {
            let file = try AVAudioFile(forWriting: url, settings: buffer.format.settings,
                                       commonFormat: buffer.format.commonFormat, interleaved: buffer.format.isInterleaved)
            try file.write(from: buffer)
        } catch {
            throw TalkbackError.audioFile(error.localizedDescription)
        }
    }
}
