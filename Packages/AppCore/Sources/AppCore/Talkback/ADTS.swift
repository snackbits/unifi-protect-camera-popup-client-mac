import Foundation

/// ADTS framing for raw AAC-LC packets (ISO/IEC 13818-7), as ffmpeg's "adts" muxer writes it:
/// 7-byte header without CRC, one frame per UDP datagram.
public enum ADTS {
    public static let headerLength = 7
    /// 13-bit frame_length field.
    public static let maxFrameLength = 0x1FFF

    private static let rates = [96_000, 88_200, 64_000, 48_000, 44_100, 32_000, 24_000,
                                22_050, 16_000, 12_000, 11_025, 8_000, 7_350]

    public static func frequencyIndex(for sampleRate: Int) -> Int? {
        rates.firstIndex(of: sampleRate)
    }

    /// nil for an unsupported rate, a channel count outside 1…7 or a frame longer than 8191 bytes.
    public static func header(payloadLength: Int, sampleRate: Int, channels: Int = 1) -> Data? {
        guard let index = frequencyIndex(for: sampleRate), (1...7).contains(channels) else { return nil }
        let length = payloadLength + headerLength
        guard payloadLength >= 0, length <= maxFrameLength else { return nil }
        let profile = 1 // AAC LC (audio object type 2) − 1
        return Data([
            0xFF,
            0xF1, // MPEG-4, layer 0, protection absent
            UInt8((profile << 6) | (index << 2) | (channels >> 2)),
            UInt8(((channels & 0x3) << 6) | (length >> 11)),
            UInt8((length >> 3) & 0xFF),
            UInt8(((length & 0x7) << 5) | 0x1F), // buffer fullness 0x7FF (VBR) …
            0xFC, // … continued, one raw data block
        ])
    }

    public static func frame(_ payload: Data, sampleRate: Int, channels: Int = 1) -> Data? {
        guard var frame = header(payloadLength: payload.count, sampleRate: sampleRate, channels: channels) else { return nil }
        frame.append(payload)
        return frame
    }
}
