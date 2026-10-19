import AVFoundation

/// Any PCM buffer (mic, file, speech) → 16-bit mono at the camera rate, with gain and clipping.
/// Not thread-safe: use from one queue.
public final class PCMResampler {
    public let outputFormat: AVAudioFormat
    public let gain: Float
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?

    public init(sampleRate: Int, gain: Float = 1) {
        outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Double(sampleRate), channels: 1, interleaved: true)!
        self.gain = max(0, gain)
    }

    public func convert(_ buffer: AVAudioPCMBuffer) throws -> [Int16] {
        guard buffer.frameLength > 0 else { return [] }
        if converter == nil || inputFormat != buffer.format {
            guard let made = AVAudioConverter(from: buffer.format, to: outputFormat) else {
                throw TalkbackError.audioFile("Format \(buffer.format.sampleRate) Hz, \(buffer.format.channelCount) Kanäle")
            }
            made.downmix = true
            converter = made
            inputFormat = buffer.format
        }
        guard let converter else { return [] }
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1_024
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return [] }
        var handedOver = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if handedOver {
                inputStatus.pointee = .noDataNow
                return nil
            }
            handedOver = true
            inputStatus.pointee = .haveData
            return buffer
        }
        if status == .error {
            throw TalkbackError.audioFile(error?.localizedDescription ?? "Umwandlung")
        }
        guard let channel = output.int16ChannelData?[0] else { return [] }
        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
        guard gain != 1 else { return samples }
        return samples.map { sample in
            let scaled = Float(sample) * gain
            return Int16(max(-32_768, min(32_767, scaled.rounded())))
        }
    }

    /// `seconds` of silence in the output format (pushes encoder and resampler delay out).
    public func silence(seconds: Double) -> [Int16] {
        [Int16](repeating: 0, count: Int(outputFormat.sampleRate * seconds))
    }
}
