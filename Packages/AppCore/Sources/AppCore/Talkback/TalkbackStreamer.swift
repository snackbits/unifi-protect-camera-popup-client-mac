import AVFoundation
import Foundation
import Network

/// Sends audio to a camera speaker: PCM → resample → AAC (ADTS) or Opus (RTP) → UDP,
/// paced in real time. Thread-safe; all work happens on one private queue.
public final class TalkbackStreamer: @unchecked Sendable {
    public enum Event: Equatable, Sendable {
        /// UDP path is up (first packet can leave).
        case ready
        /// Every packet was sent after `finish()`.
        case finished(packets: Int)
        case failed(String)
    }

    public let target: TalkbackTarget
    private let queue = DispatchQueue(label: "com.snackbits.UniFiCameraPopup.talkback", qos: .userInteractive)
    private let connection: NWConnection
    private let encoder: TalkbackEncoder
    private let resampler: PCMResampler
    private var packetizer = RTPPacketizer()
    private var pacer: RealtimePacer
    private let onEvent: @Sendable (Event) -> Void
    private let log: @Sendable (String) -> Void
    private var stopped = false
    private var finishing = false
    private var outstanding = 0
    /// Datagrams handed to the connection whose completion has not come back yet.
    private var inFlight = 0
    private var isReady = false
    private let readyTimeout: TimeInterval
    private var sent = 0
    private var reportedFirstPacket = false

    /// Throws for codecs or rates the encoder cannot produce.
    public init(
        target: TalkbackTarget,
        gain: Float = 1,
        readyTimeout: TimeInterval = 2,
        log: @escaping @Sendable (String) -> Void = { _ in },
        onEvent: @escaping @Sendable (Event) -> Void
    ) throws {
        guard let port = NWEndpoint.Port(rawValue: target.port) else {
            throw TalkbackError.invalidAddress("\(target.host):\(target.port)")
        }
        self.target = target
        encoder = try TalkbackEncoder(codec: target.codec, sampleRate: target.sampleRate)
        resampler = PCMResampler(sampleRate: target.sampleRate, gain: gain)
        pacer = RealtimePacer(sampleRate: target.sampleRate)
        let host = target.host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: .udp)
        self.readyTimeout = readyTimeout
        self.onEvent = onEvent
        self.log = log
    }

    deinit {
        connection.cancel()
    }

    public func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.isReady = true
                self.log("Talkback: UDP bereit → \(self.target.host):\(self.target.port) \(self.target.codec.rawValue) \(self.target.sampleRate) Hz, \(self.encoder.framesPerPacket) Samples/Paket")
                self.onEvent(.ready)
            case .waiting(let error):
                self.log("Talkback: UDP wartet (\(error.localizedDescription))")
            case .failed(let error):
                self.fail(error.localizedDescription)
            default:
                break
            }
        }
        connection.start(queue: queue)
        // `.waiting` (no route, Local Network denied) never resolves by itself: fail instead of
        // pretending to stream.
        queue.asyncAfter(deadline: .now() + readyTimeout) { [weak self] in
            guard let self, !self.isReady else { return }
            self.fail("UDP-Verbindung zu \(self.target.host):\(self.target.port) kommt nicht zustande")
        }
    }

    /// Takes a copy of the buffer; any PCM format and length.
    public func append(_ buffer: AVAudioPCMBuffer) {
        guard let copy = buffer.deepCopy() else { return }
        queue.async { [weak self] in
            guard let self, !self.stopped, !self.finishing else { return }
            do {
                let samples = try self.resampler.convert(copy)
                self.schedule(try self.encoder.encode(samples))
            } catch {
                self.fail(error.localizedDescription)
            }
        }
    }

    /// Ends the stream: 0.3 s of silence flushes encoder delay, then `.finished` after the last packet.
    public func finish() {
        queue.async { [weak self] in
            guard let self, !self.stopped, !self.finishing else { return }
            do {
                self.schedule(try self.encoder.encode(self.resampler.silence(seconds: 0.3)))
            } catch {
                self.fail(error.localizedDescription)
                return
            }
            self.finishing = true
            self.completeIfDone()
        }
    }

    /// Stops at once; pending packets are dropped. No event.
    public func stop() {
        queue.async { [weak self] in
            guard let self, !self.stopped else { return }
            self.stopped = true
            self.connection.cancel()
        }
    }

    // MARK: Queue-confined

    private func schedule(_ packets: [EncodedPacket]) {
        for packet in packets {
            guard let datagram = datagram(for: packet) else {
                fail("Paket zu groß (\(packet.data.count) Bytes)")
                return
            }
            let now = Self.clock()
            let due = pacer.sendTime(forSamples: packet.frames, now: now)
            outstanding += 1
            let deadline = DispatchTime.now() + max(0, due - now)
            queue.asyncAfter(deadline: deadline) { [weak self] in
                self?.send(datagram)
            }
        }
    }

    private func datagram(for packet: EncodedPacket) -> Data? {
        switch target.codec {
        case .aac:
            return ADTS.frame(packet.data, sampleRate: target.sampleRate)
        case .opus, .vorbis:
            return packetizer.packet(
                payload: packet.data,
                timestampIncrement: RTPPacketizer.timestampIncrement(frames: packet.frames, sampleRate: target.sampleRate)
            )
        }
    }

    private func send(_ datagram: Data) {
        outstanding -= 1
        guard !stopped else { return }
        inFlight += 1
        connection.send(content: datagram, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            self.queue.async {
                self.inFlight -= 1
                if let error {
                    self.fail(error.localizedDescription)
                    return
                }
                guard !self.stopped else { return }
                self.sent += 1
                if !self.reportedFirstPacket {
                    self.reportedFirstPacket = true
                    self.log("Talkback: erstes Paket gesendet (\(datagram.count) Bytes)")
                }
                self.completeIfDone()
            }
        })
    }

    private func completeIfDone() {
        guard finishing, outstanding == 0, inFlight == 0, !stopped else { return }
        stopped = true
        log("Talkback: fertig, \(sent) Pakete")
        let count = sent
        // Give the last datagram a moment to leave before the connection goes away.
        queue.asyncAfter(deadline: .now() + 0.1) { [connection] in connection.cancel() }
        onEvent(.finished(packets: count))
    }

    private func fail(_ message: String) {
        guard !stopped else { return }
        stopped = true
        connection.cancel()
        log("Talkback: Fehler – \(message)")
        onEvent(.failed(message))
    }

    private static func clock() -> TimeInterval {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
    }
}
