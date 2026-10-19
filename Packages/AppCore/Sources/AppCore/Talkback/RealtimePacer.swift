import Foundation

/// Real-time pacing like uiprotect's TalkbackStream: packet n leaves at
/// start + samplesBefore / rate (absolute schedule, no drift). UDP has no flow control,
/// so sending faster than real time floods the camera. When the source falls behind by more
/// than `maxLag` (a stalled microphone), the schedule is re-anchored instead of bursting.
public struct RealtimePacer: Sendable {
    public let sampleRate: Double
    public let maxLag: TimeInterval
    public private(set) var scheduledSamples = 0
    private var anchor: TimeInterval?

    public init(sampleRate: Int, maxLag: TimeInterval = 0.25) {
        self.sampleRate = Double(max(sampleRate, 1))
        self.maxLag = maxLag
    }

    /// When the next packet (holding `samples` samples) should be sent; never earlier than `now`.
    public mutating func sendTime(forSamples samples: Int, now: TimeInterval) -> TimeInterval {
        let start = anchor ?? now
        anchor = start
        var due = start + Double(scheduledSamples) / sampleRate
        if due < now - maxLag {
            anchor = now - Double(scheduledSamples) / sampleRate
            due = now
        }
        scheduledSamples += samples
        return max(due, now)
    }
}
