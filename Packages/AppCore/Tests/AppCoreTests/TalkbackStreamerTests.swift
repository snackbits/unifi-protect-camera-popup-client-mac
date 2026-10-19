import AVFoundation
import Network
import XCTest
@testable import AppCore

/// Receives UDP datagrams on 127.0.0.1 like a camera speaker would.
final class UDPSink: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "udp-sink")
    private let lock = NSLock()
    private var datagrams: [(Data, TimeInterval)] = []
    private var connections: [NWConnection] = []

    init() throws {
        let parameters = NWParameters.udp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }

    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
            let once = OnceFlag()
            listener.stateUpdateHandler = { [listener] state in
                switch state {
                case .ready:
                    if once.claim() { continuation.resume(returning: listener.port?.rawValue ?? 0) }
                case .failed(let error):
                    if once.claim() { continuation.resume(throwing: error) }
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                self.lock.withLock { self.connections.append(connection) }
                connection.start(queue: self.queue)
                self.receive(on: connection)
            }
            listener.start(queue: queue)
        }
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let data {
                let now = Double(DispatchTime.now().uptimeNanoseconds) / 1e9
                self.lock.withLock { self.datagrams.append((data, now)) }
            }
            if error == nil { self.receive(on: connection) }
        }
    }

    var received: [(Data, TimeInterval)] { lock.withLock { datagrams } }

    func stop() {
        listener.cancel()
        lock.withLock { connections.forEach { $0.cancel() } }
    }
}

final class TalkbackStreamerTests: XCTestCase {
    private func sineBuffer(seconds: Double, rate: Double = 44_100) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let frames = AVAudioFrameCount(seconds * rate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for index in 0..<Int(frames) {
            buffer.floatChannelData![0][index] = Float(0.4 * sin(2 * .pi * 440 * Double(index) / rate))
        }
        return buffer
    }

    private func stream(codec: TalkbackCodec, rate: Int, seconds: Double) async throws -> (packets: [(Data, TimeInterval)], event: TalkbackStreamer.Event) {
        let sink = try UDPSink()
        let port = try await sink.start()
        defer { sink.stop() }
        let finished = expectation(description: "finished")
        let box = EventBox()
        let streamer = try TalkbackStreamer(
            target: TalkbackTarget(host: "127.0.0.1", port: port, codec: codec, sampleRate: rate)
        ) { event in
            guard event != .ready, box.set(event) else { return }
            finished.fulfill()
        }
        streamer.start()
        streamer.append(sineBuffer(seconds: seconds))
        streamer.finish()
        await fulfillment(of: [finished], timeout: seconds + 5)
        try await Task.sleep(nanoseconds: 300_000_000)
        return (sink.received, try XCTUnwrap(box.value))
    }

    func testOpusIsSentAsPacedRTP() async throws {
        let result = try await stream(codec: .opus, rate: 48_000, seconds: 1)
        guard case .finished(let count) = result.event else { return XCTFail("\(result.event)") }
        XCTAssertGreaterThanOrEqual(result.packets.count, 50)
        XCTAssertEqual(result.packets.count, count)
        let first = [UInt8](result.packets[0].0)
        XCTAssertEqual(first[0], 0x80)
        XCTAssertEqual(first[1], 0xE1)
        let sequences = result.packets.map { UInt16($0.0[2]) << 8 | UInt16($0.0[3]) }
        for (a, b) in zip(sequences, sequences.dropFirst()) { XCTAssertEqual(b, a &+ 1) }
        // Real time: 1.3 s of audio (incl. 0.3 s flush) must not arrive in a burst.
        let span = result.packets.last!.1 - result.packets.first!.1
        XCTAssertGreaterThan(span, 1.1)
        XCTAssertLessThan(span, 1.6)
    }

    func testAACIsSentAsADTSFrames() async throws {
        let result = try await stream(codec: .aac, rate: 16_000, seconds: 0.5)
        guard case .finished = result.event else { return XCTFail("\(result.event)") }
        XCTAssertGreaterThan(result.packets.count, 8)
        for (datagram, _) in result.packets {
            XCTAssertEqual(datagram[0], 0xFF)
            XCTAssertEqual(datagram[1], 0xF1)
            let length = (Int(datagram[3] & 0x03) << 11) | (Int(datagram[4]) << 3) | (Int(datagram[5]) >> 5)
            XCTAssertEqual(length, datagram.count)
        }
    }

    func testUnreachableTargetFailsInsteadOfFinishing() async throws {
        let failed = expectation(description: "failed")
        let box = EventBox()
        let streamer = try TalkbackStreamer(
            target: TalkbackTarget(host: "no-such-host.invalid", port: 7004, codec: .opus, sampleRate: 48_000),
            readyTimeout: 1
        ) { event in
            guard event != .ready, box.set(event) else { return }
            failed.fulfill()
        }
        streamer.start()
        streamer.append(sineBuffer(seconds: 0.2))
        streamer.finish()
        await fulfillment(of: [failed], timeout: 6)
        guard case .failed = try XCTUnwrap(box.value) else { return XCTFail("\(String(describing: box.value))") }
    }

    func testDroppingStreamerWithoutStopDoesNotCrash() async throws {
        let sink = try UDPSink()
        let port = try await sink.start()
        defer { sink.stop() }
        var streamer: TalkbackStreamer? = try TalkbackStreamer(
            target: TalkbackTarget(host: "127.0.0.1", port: port, codec: .opus, sampleRate: 48_000)
        ) { _ in }
        streamer?.start()
        streamer?.append(sineBuffer(seconds: 1))
        streamer = nil
        try await Task.sleep(nanoseconds: 400_000_000)
    }

    func testStopDropsPendingPackets() async throws {
        let sink = try UDPSink()
        let port = try await sink.start()
        defer { sink.stop() }
        let streamer = try TalkbackStreamer(
            target: TalkbackTarget(host: "127.0.0.1", port: port, codec: .opus, sampleRate: 48_000)
        ) { _ in }
        streamer.start()
        streamer.append(sineBuffer(seconds: 3))
        try await Task.sleep(nanoseconds: 500_000_000)
        streamer.stop()
        try await Task.sleep(nanoseconds: 500_000_000)
        let afterStop = sink.received.count
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(sink.received.count, afterStop)
        XCTAssertLessThan(afterStop, 60)
    }
}

final class EventBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: TalkbackStreamer.Event?
    var value: TalkbackStreamer.Event? { lock.withLock { stored } }
    /// true only for the first event.
    func set(_ event: TalkbackStreamer.Event) -> Bool {
        lock.withLock {
            guard stored == nil else { return false }
            stored = event
            return true
        }
    }
}

final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false
    func claim() -> Bool {
        lock.withLock {
            guard !used else { return false }
            used = true
            return true
        }
    }
}

extension TalkbackStreamerTests {
    /// A finished streamer must be freed once its owner lets go (no cycle through the event closure).
    func testFinishedStreamerIsDeallocated() async throws {
        let sink = try UDPSink()
        let port = try await sink.start()
        defer { sink.stop() }
        let finished = expectation(description: "finished")
        let box = EventBox()
        weak var weakStreamer: TalkbackStreamer?
        do {
            let streamer = try TalkbackStreamer(
                target: TalkbackTarget(host: "127.0.0.1", port: port, codec: .opus, sampleRate: 48_000)
            ) { event in
                guard event != .ready, box.set(event) else { return }
                finished.fulfill()
            }
            weakStreamer = streamer
            streamer.start()
            streamer.append(sineBuffer(seconds: 0.2))
            streamer.finish()
            await fulfillment(of: [finished], timeout: 5)
        }
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertNil(weakStreamer)
    }
}
