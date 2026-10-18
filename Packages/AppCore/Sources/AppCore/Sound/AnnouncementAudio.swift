import AVFoundation
import Foundation

/// Loads announcement audio and renders text with macOS voices (no network, no GPL engines).
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

    /// German voices first (premium, enhanced, default), then by name.
    public static func voices(language: String = "de") -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.lowercased().hasPrefix(language.lowercased()) }
            .sorted { lhs, rhs in
                if lhs.quality != rhs.quality { return lhs.quality.rawValue > rhs.quality.rawValue }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    /// "Anna (Premium) · macOS" – template wording of the voice pop-up.
    public static func label(for voice: AVSpeechSynthesisVoice) -> String {
        let quality: String
        switch voice.quality {
        case .premium: quality = " (Premium)"
        case .enhanced: quality = " (Erweitert)"
        default: quality = ""
        }
        return "\(voice.name)\(quality) · macOS"
    }

    /// Speaks `text` into a buffer (`AVSpeechSynthesizer.write`). Unknown voice = system default German voice.
    public static func render(text: String, voiceIdentifier: String?) async throws -> AVAudioPCMBuffer {
        let utterance = AVSpeechUtterance(string: text)
        if let voiceIdentifier, let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            utterance.voice = voice
        } else {
            utterance.voice = voices().first ?? AVSpeechSynthesisVoice(language: "de-DE")
        }
        let collector = SpeechCollector()
        return try await withCheckedThrowingContinuation { continuation in
            collector.start(utterance) { result in
                continuation.resume(with: result)
            }
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

    /// Writes a buffer as CAF (used to cache rendered speech).
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

/// Keeps the synthesizer alive and concatenates its buffers; a zero-length buffer ends the utterance.
private final class SpeechCollector: @unchecked Sendable {
    private let synthesizer = AVSpeechSynthesizer()
    private var chunks: [AVAudioPCMBuffer] = []
    private var done = false
    private let lock = NSLock()

    func start(_ utterance: AVSpeechUtterance, completion: @escaping (Result<AVAudioPCMBuffer, Error>) -> Void) {
        synthesizer.write(utterance) { [self] buffer in
            guard let pcm = buffer as? AVAudioPCMBuffer else { return }
            let finished: Bool = lock.withLock {
                guard !done else { return false }
                if pcm.frameLength == 0 {
                    done = true
                    return true
                }
                if let copy = pcm.deepCopy() { chunks.append(copy) }
                return false
            }
            guard finished else { return }
            let parts = lock.withLock { chunks }
            if let joined = Self.join(parts) {
                completion(.success(joined))
            } else {
                completion(.failure(TalkbackError.speechFailed))
            }
            withExtendedLifetime(self) {}
        }
    }

    private static func join(_ parts: [AVAudioPCMBuffer]) -> AVAudioPCMBuffer? {
        guard let format = parts.first?.format else { return nil }
        let total = parts.reduce(0) { $0 + $1.frameLength }
        guard total > 0, let joined = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: total) else { return nil }
        let bytesPerFrame = Int(format.streamDescription.pointee.mBytesPerFrame)
        let target = UnsafeMutableAudioBufferListPointer(joined.mutableAudioBufferList)
        var offset = 0
        for part in parts where part.format == format {
            let source = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: part.audioBufferList))
            let bytes = Int(part.frameLength) * bytesPerFrame
            for (from, to) in zip(source, target) {
                guard let src = from.mData, let dst = to.mData else { continue }
                memcpy(dst.advanced(by: offset), src, bytes)
            }
            offset += bytes
        }
        joined.frameLength = AVAudioFrameCount(offset / bytesPerFrame)
        return joined
    }
}
