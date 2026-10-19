import Foundation

/// RTP for Opus (RFC 7587), matching ffmpeg's RTP muxer: one Opus packet per RTP packet,
/// dynamic payload type 97, 48 kHz timestamp clock, marker bit set, random start values.
public struct RTPPacketizer: Sendable {
    public static let opusPayloadType: UInt8 = 97
    /// RFC 7587: the RTP clock of Opus is always 48 kHz, whatever the encoder rate.
    public static let opusClockRate = 48_000
    public static let headerLength = 12

    public let payloadType: UInt8
    public let ssrc: UInt32
    public private(set) var sequenceNumber: UInt16
    public private(set) var timestamp: UInt32

    public init(
        payloadType: UInt8 = RTPPacketizer.opusPayloadType,
        sequenceNumber: UInt16 = .random(in: 0...UInt16.max),
        timestamp: UInt32 = .random(in: 0...UInt32.max),
        ssrc: UInt32 = .random(in: 0...UInt32.max)
    ) {
        self.payloadType = payloadType & 0x7F
        self.sequenceNumber = sequenceNumber
        self.timestamp = timestamp
        self.ssrc = ssrc
    }

    /// Timestamp increment of a packet with `frames` samples at `sampleRate`.
    public static func timestampIncrement(frames: Int, sampleRate: Int) -> UInt32 {
        UInt32(frames * opusClockRate / max(sampleRate, 1))
    }

    /// Builds the next packet and advances sequence number and timestamp (both wrap).
    public mutating func packet(payload: Data, timestampIncrement: UInt32) -> Data {
        var data = Data(capacity: Self.headerLength + payload.count)
        data.append(0x80) // version 2, no padding, no extension, no CSRC
        data.append(0x80 | payloadType) // marker + payload type
        data.append(UInt8(sequenceNumber >> 8))
        data.append(UInt8(sequenceNumber & 0xFF))
        for shift in stride(from: 24, through: 0, by: -8) {
            data.append(UInt8((timestamp >> UInt32(shift)) & 0xFF))
        }
        for shift in stride(from: 24, through: 0, by: -8) {
            data.append(UInt8((ssrc >> UInt32(shift)) & 0xFF))
        }
        data.append(payload)
        sequenceNumber &+= 1
        timestamp &+= timestampIncrement
        return data
    }
}
