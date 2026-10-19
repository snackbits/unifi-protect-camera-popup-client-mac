import AVFoundation

extension AVAudioPCMBuffer {
    /// Independent copy (tap and synthesizer buffers are reused after their callback returns).
    func deepCopy() -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: max(frameLength, 1)) else { return nil }
        copy.frameLength = frameLength
        let bytes = Int(frameLength) * Int(format.streamDescription.pointee.mBytesPerFrame)
        let source = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: audioBufferList))
        let target = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for (from, to) in zip(source, target) {
            guard let src = from.mData, let dst = to.mData else { continue }
            memcpy(dst, src, min(bytes, Int(from.mDataByteSize), Int(to.mDataByteSize)))
        }
        return copy
    }
}
