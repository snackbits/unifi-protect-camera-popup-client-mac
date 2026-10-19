import Foundation

/// The parts of a RIFF/WAVE header Piper's output is checked against (16-bit PCM).
public struct WAVInfo: Equatable, Sendable {
    public let channels: Int
    public let sampleRate: Int
    public let bitsPerSample: Int
    /// Byte offset of the first sample and number of sample bytes (clamped to the file).
    public let dataOffset: Int
    public let dataLength: Int

    public var duration: TimeInterval {
        let frameBytes = channels * bitsPerSample / 8
        guard frameBytes > 0, sampleRate > 0 else { return 0 }
        return Double(dataLength / frameBytes) / Double(sampleRate)
    }

    /// Walks the chunks (fmt may be followed by LIST etc.); nil unless PCM (format 1) with a data chunk.
    public static func parse(_ data: Data) -> WAVInfo? {
        let bytes = [UInt8](data)
        guard bytes.count >= 12, bytes[0..<4] == [0x52, 0x49, 0x46, 0x46], bytes[8..<12] == [0x57, 0x41, 0x56, 0x45] else {
            return nil
        }
        func u16(_ at: Int) -> Int { Int(bytes[at]) | Int(bytes[at + 1]) << 8 }
        func u32(_ at: Int) -> Int { u16(at) | u16(at + 2) << 16 }
        var offset = 12
        var format: (channels: Int, rate: Int, bits: Int)?
        while offset + 8 <= bytes.count {
            let id = bytes[offset..<offset + 4]
            let size = u32(offset + 4)
            let body = offset + 8
            if id == [0x66, 0x6D, 0x74, 0x20] { // "fmt "
                guard size >= 16, body + 16 <= bytes.count, u16(body) == 1 else { return nil }
                format = (u16(body + 2), u32(body + 4), u16(body + 14))
            } else if id == [0x64, 0x61, 0x74, 0x61] { // "data"
                guard let format, format.channels > 0, format.rate > 0, format.bits == 16 else { return nil }
                return WAVInfo(channels: format.channels, sampleRate: format.rate, bitsPerSample: format.bits,
                               dataOffset: body, dataLength: min(size, bytes.count - body))
            }
            offset = body + size + (size & 1)
        }
        return nil
    }

    /// 16-bit samples as −1…1, all channels averaged (for the silence check before a file is kept).
    public static func monoSamples(_ data: Data, info: WAVInfo) -> [Float] {
        let frameBytes = info.channels * 2
        let frames = info.dataLength / frameBytes
        guard frames > 0 else { return [] }
        return data.withUnsafeBytes { raw -> [Float] in
            var out = [Float](repeating: 0, count: frames)
            for frame in 0..<frames {
                var sum: Float = 0
                for channel in 0..<info.channels {
                    let at = info.dataOffset + frame * frameBytes + channel * 2
                    let value = Int16(bitPattern: UInt16(raw[at]) | UInt16(raw[at + 1]) << 8)
                    sum += Float(value) / 32_768
                }
                out[frame] = sum / Float(info.channels)
            }
            return out
        }
    }

    /// Piper's output is usable: PCM 16-bit and at least one block above the loudness gate
    /// (empty or unspeakable text gives 0.2 s of silence).
    public static func hasSpeech(_ data: Data) -> Bool {
        guard let info = parse(data) else { return false }
        return Loudness.gatedRMSdB(monoSamples(data, info: info), sampleRate: Double(info.sampleRate)) != nil
    }
}
