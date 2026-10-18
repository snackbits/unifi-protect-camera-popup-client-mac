import AudioToolbox
import Foundation

/// One compressed packet and how many PCM samples (at the encoder rate) it carries.
public struct EncodedPacket: Equatable, Sendable {
    public let data: Data
    public let frames: Int
}

/// 16-bit mono PCM → AAC-LC (raw, for ADTS) or Opus with the system encoders (AudioToolbox).
/// Not thread-safe: use from one queue.
public final class TalkbackEncoder {
    public let codec: TalkbackCodec
    public let sampleRate: Int
    /// Samples per packet: AAC 1024, Opus 20 ms.
    public let framesPerPacket: Int

    private var converter: AudioConverterRef?
    private var pending: [Int16] = []
    /// Samples before this index were handed to the converter already (compacted in bulk).
    private var readIndex = 0
    /// Memory handed to the converter must stay valid until its next input callback.
    private var supplied: UnsafeMutablePointer<Int16>?
    private var suppliedCapacity = 0
    private let maxPacketSize: Int
    private let outputBuffer: UnsafeMutableRawPointer

    /// Returned from the input callback when all pending samples are used up.
    private static let needMoreInput: OSStatus = 0x6E6D6F72 // 'nmor'

    public init(codec: TalkbackCodec, sampleRate: Int) throws {
        guard codec != .vorbis else { throw TalkbackError.unsupportedCodec(codec.rawValue) }
        guard codec.supportedSampleRates.contains(sampleRate) else { throw TalkbackError.unsupportedSampleRate(sampleRate) }
        self.codec = codec
        self.sampleRate = sampleRate

        var input = AudioStreamBasicDescription(
            mSampleRate: Double(sampleRate),
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        var output = AudioStreamBasicDescription()
        output.mSampleRate = Double(sampleRate)
        output.mChannelsPerFrame = 1
        switch codec {
        case .aac:
            output.mFormatID = kAudioFormatMPEG4AAC
            output.mFormatFlags = UInt32(MPEG4ObjectID.AAC_LC.rawValue)
            output.mFramesPerPacket = 1024
        case .opus, .vorbis:
            output.mFormatID = kAudioFormatOpus
            output.mFramesPerPacket = UInt32(sampleRate / 50)
        }

        var created: AudioConverterRef?
        let status = AudioConverterNew(&input, &output, &created)
        guard status == noErr, let created else { throw TalkbackError.encoder(status) }
        converter = created

        // What the encoder actually uses (it may round the packet size).
        var actual = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        if AudioConverterGetProperty(created, kAudioConverterCurrentOutputStreamDescription, &size, &actual) == noErr,
           actual.mFramesPerPacket > 0 {
            framesPerPacket = Int(actual.mFramesPerPacket)
        } else {
            framesPerPacket = Int(output.mFramesPerPacket)
        }

        var maxSize: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        if AudioConverterGetProperty(created, kAudioConverterPropertyMaximumOutputPacketSize, &size, &maxSize) != noErr || maxSize == 0 {
            maxSize = 8_192
        }
        maxPacketSize = Int(maxSize)
        outputBuffer = UnsafeMutableRawPointer.allocate(byteCount: Int(maxSize), alignment: 16)
    }

    deinit {
        if let converter { AudioConverterDispose(converter) }
        supplied?.deallocate()
        outputBuffer.deallocate()
    }

    /// Feeds samples, returns every packet that is complete now (may be none: encoder delay).
    public func encode(_ samples: [Int16]) throws -> [EncodedPacket] {
        if readIndex > 0, readIndex >= pending.count / 2 {
            pending.removeFirst(readIndex)
            readIndex = 0
        }
        pending.append(contentsOf: samples)
        guard let converter else { return [] }
        var packets: [EncodedPacket] = []
        while true {
            var packetCount: UInt32 = 1
            var description = AudioStreamPacketDescription()
            var bufferList = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(maxPacketSize), mData: outputBuffer)
            )
            let status = AudioConverterFillComplexBuffer(
                converter,
                { _, ioPackets, ioData, _, userData -> OSStatus in
                    let encoder = Unmanaged<TalkbackEncoder>.fromOpaque(userData!).takeUnretainedValue()
                    return encoder.supply(ioPackets, ioData)
                },
                Unmanaged.passUnretained(self).toOpaque(),
                &packetCount,
                &bufferList,
                &description
            )
            if packetCount > 0 {
                let byteCount = Int(bufferList.mBuffers.mDataByteSize)
                let offset = Int(description.mStartOffset)
                let length = description.mDataByteSize > 0 ? Int(description.mDataByteSize) : byteCount
                if length > 0 {
                    packets.append(EncodedPacket(
                        data: Data(bytes: outputBuffer.advanced(by: offset), count: length),
                        frames: framesPerPacket
                    ))
                }
            }
            if status == Self.needMoreInput || packetCount == 0 { break }
            guard status == noErr else { throw TalkbackError.encoder(status) }
        }
        return packets
    }

    /// Input callback: hands over as many pending samples as the converter asks for.
    private func supply(
        _ ioPackets: UnsafeMutablePointer<UInt32>,
        _ ioData: UnsafeMutablePointer<AudioBufferList>
    ) -> OSStatus {
        let available = pending.count - readIndex
        guard available > 0 else {
            ioPackets.pointee = 0
            ioData.pointee.mBuffers.mDataByteSize = 0
            return Self.needMoreInput
        }
        let requested = Int(ioPackets.pointee)
        let count = requested > 0 ? min(requested, available) : available
        if suppliedCapacity < count {
            supplied?.deallocate()
            supplied = UnsafeMutablePointer<Int16>.allocate(capacity: count)
            suppliedCapacity = count
        }
        pending.withUnsafeBufferPointer { source in
            supplied!.update(from: source.baseAddress! + readIndex, count: count)
        }
        readIndex += count
        ioPackets.pointee = UInt32(count)
        ioData.pointee.mNumberBuffers = 1
        ioData.pointee.mBuffers.mNumberChannels = 1
        ioData.pointee.mBuffers.mDataByteSize = UInt32(count * 2)
        ioData.pointee.mBuffers.mData = UnsafeMutableRawPointer(supplied!)
        return noErr
    }
}
