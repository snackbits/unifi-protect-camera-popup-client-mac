import XCTest
@testable import ProtectKit

final class TalkbackSessionTests: XCTestCase {
    private let base = "/proxy/protect/integration/v1"

    override func setUp() {
        StubProtocol.responses = [:]
        StubProtocol.requests = []
        StubProtocol.redirects = [:]
    }

    func testParsesDocumentedAnswer() throws {
        let session = try TalkbackSession.parse(Data(#"{"url":"rtp://192.168.1.20:7004","codec":"opus","samplingRate":48000,"bitsPerSample":16}"#.utf8))
        XCTAssertEqual(session.host, "192.168.1.20")
        XCTAssertEqual(session.port, 7004)
        XCTAssertEqual(session.codec, "opus")
        XCTAssertEqual(session.samplingRate, 48_000)
        XCTAssertEqual(session.bitsPerSample, 16)
        XCTAssertTrue(session.raw.contains("rtp://"))
    }

    func testToleratesVariants() throws {
        let wrapped = try TalkbackSession.parse(Data(#"{"data":{"url":"udp://cam.local","codec":"AAC","samplingRate":"22050"}}"#.utf8))
        XCTAssertEqual(wrapped.host, "cam.local")
        XCTAssertEqual(wrapped.port, TalkbackSession.defaultPort)
        XCTAssertEqual(wrapped.samplingRate, 22_050)
        XCTAssertEqual(wrapped.bitsPerSample, 16)
        let bare = try TalkbackSession.parse(Data(#"[{"uri":"10.0.0.5:7010","typeFmt":"aac","sampleRate":16000.0}]"#.utf8))
        XCTAssertEqual(bare.host, "10.0.0.5")
        XCTAssertEqual(bare.port, 7010)
        XCTAssertEqual(bare.codec, "aac")
        XCTAssertEqual(bare.samplingRate, 16_000)
        let ipv6 = try TalkbackSession.parse(Data(#"{"url":"rtp://[fe80::1]:7004","codec":"opus"}"#.utf8))
        XCTAssertEqual(ipv6.host, "fe80::1")
        XCTAssertEqual(ipv6.samplingRate, 0)
    }

    func testRejectsAnswersWithoutTarget() {
        for body in [#"{}"#, #"{"url":""}"#, #"{"url":"rtp://:7004"}"#, #"{"url":"rtp://cam:0"}"#, "nonsense", #""text""#] {
            XCTAssertThrowsError(try TalkbackSession.parse(Data(body.utf8)), body) {
                XCTAssertEqual($0 as? ProtectError, .decoding)
            }
        }
    }

    func testClientPostsWithKey() async throws {
        StubProtocol.responses["POST \(base)/cameras/cam1/talkback-session"] = (200, Data(#"{"url":"rtp://192.168.1.20:7004","codec":"opus","samplingRate":48000}"#.utf8))
        let client = ProtectClient(host: "192.168.1.1", apiKey: "KEY", pinnedFingerprint: nil, onNewFingerprint: { _ in }, protocolClasses: [StubProtocol.self])
        defer { client.invalidate() }
        let session = try await client.talkbackSession(cameraId: "cam1")
        XCTAssertEqual(session.port, 7004)
        let request = try XCTUnwrap(StubProtocol.requests.last)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-KEY"), "KEY")
    }

    func testClientMapsHTTPErrors() async {
        StubProtocol.responses["POST \(base)/cameras/cam1/talkback-session"] = (404, Data())
        let client = ProtectClient(host: "192.168.1.1", apiKey: "KEY", pinnedFingerprint: nil, onNewFingerprint: { _ in }, protocolClasses: [StubProtocol.self])
        defer { client.invalidate() }
        do { _ = try await client.talkbackSession(cameraId: "cam1"); XCTFail() } catch {
            XCTAssertEqual(error as? ProtectError, .http(404))
        }
    }
}
