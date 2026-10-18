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

    /// The voice every new rendering uses (Anna, else the best German voice).
    public static func preferredVoice() -> AVSpeechSynthesisVoice? {
        let all = voices()
        guard let pick = VoiceChoice.pick(from: all.map(candidate)) else { return nil }
        return all.first { $0.identifier == pick.identifier }
    }

    public static func candidate(_ voice: AVSpeechSynthesisVoice) -> VoiceChoice.Candidate {
        let quality: Int
        switch voice.quality {
        case .premium: quality = 3
        case .enhanced: quality = 2
        default: quality = 1
        }
        return VoiceChoice.Candidate(identifier: voice.identifier, name: voice.name, language: voice.language, quality: quality)
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

    /// Speaks `text` into a buffer (`AVSpeechSynthesizer.write`). Unknown voice = `preferredVoice()`.
    /// Fails with `.speechFailed` for empty text or when the synthesizer does not finish within `timeout`
    /// (default 20 s + 0.15 s per character); honours task cancellation.
    public static func render(text: String, voiceIdentifier: String?, timeout: TimeInterval? = nil) async throws -> AVAudioPCMBuffer {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TalkbackError.speechFailed }
        let utterance = AVSpeechUtterance(string: trimmed)
        if let voiceIdentifier, let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            utterance.voice = voice
        } else {
            utterance.voice = preferredVoice() ?? AVSpeechSynthesisVoice(language: "de-DE")
        }
        let limit = timeout ?? (20 + 0.15 * Double(trimmed.count))
        let collector = SpeechCollector()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                collector.start(utterance, timeout: limit) { continuation.resume(with: $0) }
            }
        } onCancel: {
            collector.cancel()
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
/// Completes exactly once (result, timeout or cancellation) and then releases the synthesizer.
private final class SpeechCollector: @unchecked Sendable {
    private var synthesizer: AVSpeechSynthesizer?
    private var chunks: [AVAudioPCMBuffer] = []
    private var done = false
    private var cancelled = false
    private var completion: ((Result<AVAudioPCMBuffer, Error>) -> Void)?
    private let lock = NSLock()

    func start(_ utterance: AVSpeechUtterance, timeout: TimeInterval,
               completion: @escaping (Result<AVAudioPCMBuffer, Error>) -> Void) {
        let synth = AVSpeechSynthesizer()
        let alreadyCancelled: Bool = lock.withLock {
            self.completion = completion
            if cancelled { return true }
            synthesizer = synth
            return false
        }
        if alreadyCancelled { finish(.failure(CancellationError())); return }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
            self?.finish(.failure(TalkbackError.speechFailed))
        }
        synth.write(utterance) { [weak self] buffer in
            guard let self, let pcm = buffer as? AVAudioPCMBuffer else { return }
            let ended: Bool = self.lock.withLock {
                guard !self.done else { return false }
                if pcm.frameLength == 0 { return true }
                if let copy = pcm.deepCopy() { self.chunks.append(copy) }
                return false
            }
            guard ended else { return }
            if let joined = Self.join(self.lock.withLock { self.chunks }) {
                self.finish(.success(joined))
            } else {
                self.finish(.failure(TalkbackError.speechFailed))
            }
        }
    }

    func cancel() {
        lock.withLock { cancelled = true }
        finish(.failure(CancellationError()))
    }

    private func finish(_ result: Result<AVAudioPCMBuffer, Error>) {
        let (callback, synth): (((Result<AVAudioPCMBuffer, Error>) -> Void)?, AVSpeechSynthesizer?) = lock.withLock {
            guard !done, let callback = completion else { return (nil, nil) }
            done = true
            let synth = synthesizer
            synthesizer = nil
            completion = nil
            chunks = []
            return (callback, synth)
        }
        synth?.stopSpeaking(at: .immediate)
        callback?(result)
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
