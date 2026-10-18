import XCTest
@testable import ProtectKit

/// Serves canned responses keyed by "METHOD path".
final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var responses: [String: (Int, Data)] = [:]
    nonisolated(unsafe) static var requests: [URLRequest] = []
    /// "METHOD path" -> absolute Location of a 302 answer.
    nonisolated(unsafe) static var redirects: [String: String] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        let key = "\(request.httpMethod ?? "GET") \(request.url?.path ?? "")"
        if let location = Self.redirects[key], let target = URL(string: location) {
            let resp = HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: nil, headerFields: ["Location": location])!
            var next = request
            next.url = target
            client?.urlProtocol(self, wasRedirectedTo: next, redirectResponse: resp)
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data())
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let (status, body) = Self.responses[key] ?? (404, Data())
        let resp = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class ProtectClientTests: XCTestCase {
    private let base = "/proxy/protect/integration/v1"

    override func setUp() {
        StubProtocol.responses = [:]
        StubProtocol.requests = []
        StubProtocol.redirects = [:]
    }

    private func client() -> ProtectClient {
        ProtectClient(host: "192.168.1.1", apiKey: "KEY", pinnedFingerprint: nil, onNewFingerprint: { _ in }, protocolClasses: [StubProtocol.self])
    }

    func testBaseURL() {
        XCTAssertEqual(ProtectClient.baseURL(for: "192.168.1.1")?.absoluteString, "https://192.168.1.1/proxy/protect/integration")
        XCTAssertEqual(ProtectClient.baseURL(for: " https://konsole.local/ ")?.absoluteString, "https://konsole.local/proxy/protect/integration")
        XCTAssertEqual(ProtectClient.baseURL(for: "konsole.local:8443")?.absoluteString, "https://konsole.local:8443/proxy/protect/integration")
        XCTAssertNil(ProtectClient.baseURL(for: ""))
    }

    func testCanonicalHost() {
        XCTAssertEqual(ProtectClient.canonicalHost(" 192.168.1.1 "), "192.168.1.1")
        XCTAssertEqual(ProtectClient.canonicalHost("https://192.168.1.1/"), "192.168.1.1")
        XCTAssertEqual(ProtectClient.canonicalHost("192.168.1.1/"), "192.168.1.1")
        XCTAssertEqual(ProtectClient.canonicalHost("192.168.1.1:443"), "192.168.1.1")
        XCTAssertEqual(ProtectClient.canonicalHost("HTTPS://Konsole.Local"), "konsole.local")
        XCTAssertEqual(ProtectClient.canonicalHost("konsole.local:8443"), "konsole.local:8443")
        XCTAssertEqual(ProtectClient.canonicalHost("https://Konsole.local:8443/x"), "konsole.local:8443")
        XCTAssertNil(ProtectClient.canonicalHost(""))
        XCTAssertNil(ProtectClient.canonicalHost("   "))
    }

    func testRefusesRedirectsSoTheKeyIsNeverForwarded() async {
        StubProtocol.redirects["GET \(base)/meta/info"] = "https://evil.example/steal"
        do { _ = try await client().metaInfo(); XCTFail("redirect must not be followed") } catch {
            XCTAssertEqual(error as? ProtectError, .http(302))
        }
        XCTAssertEqual(StubProtocol.requests.count, 1)
        XCTAssertFalse(StubProtocol.requests.contains { $0.url?.host == "evil.example" })
    }

    func testEventsWebSocketSetsApiKeyHeader() {
        let c = client()
        defer { c.invalidate() }
        let task = c.eventsWebSocket()
        defer { task.cancel() }
        let request = task.originalRequest ?? task.currentRequest
        XCTAssertEqual(request?.url?.absoluteString, "wss://192.168.1.1/proxy/protect/integration/v1/subscribe/events")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "X-API-KEY"), "KEY")
    }

    func testEventsWebSocketOmitsApiKeyHeaderWhenKeyIsEmpty() {
        let c = ProtectClient(host: "192.168.1.1", apiKey: "", pinnedFingerprint: nil, onNewFingerprint: { _ in }, protocolClasses: [StubProtocol.self])
        defer { c.invalidate() }
        let task = c.eventsWebSocket()
        defer { task.cancel() }
        let request = task.originalRequest ?? task.currentRequest
        XCTAssertNotNil(request)
        XCTAssertNil(request?.value(forHTTPHeaderField: "X-API-KEY"))
        XCTAssertFalse(request?.allHTTPHeaderFields?.keys.contains { $0.lowercased() == "x-api-key" } ?? true)
    }

    func testSendsApiKeyAndDecodesCameras() async throws {
        StubProtocol.responses["GET \(base)/cameras"] = (200, try fixture("cameras"))
        let cams = try await client().cameras()
        XCTAssertEqual(cams.map(\.id), ["cam-door", "cam-drive", "cam-old"])
        XCTAssertEqual(StubProtocol.requests.first?.value(forHTTPHeaderField: "X-API-KEY"), "KEY")
    }

    func testOmitsApiKeyHeaderWhenKeyIsEmpty() async {
        StubProtocol.responses["GET \(base)/meta/info"] = (401, Data())
        let c = ProtectClient(host: "192.168.1.1", apiKey: "", pinnedFingerprint: nil, onNewFingerprint: { _ in }, protocolClasses: [StubProtocol.self])
        _ = try? await c.metaInfo()
        XCTAssertEqual(StubProtocol.requests.count, 1)
        XCTAssertNil(StubProtocol.requests.first?.value(forHTTPHeaderField: "X-API-KEY"))
        XCTAssertFalse(StubProtocol.requests.first?.allHTTPHeaderFields?.keys.contains { $0.lowercased() == "x-api-key" } ?? true)
    }

    // The fingerprint capture itself needs a real TLS handshake; it is covered by the
    // evaluate(trust:) tests in PinEnforcementTests. Here: no handshake -> error, and no key sent.
    func testProbeWithoutHandshakeThrowsAndSendsNoKey() async {
        StubProtocol.responses["GET \(base)/meta/info"] = (401, Data())
        do {
            _ = try await ProtectClient.probeFingerprint(host: "192.168.1.1", protocolClasses: [StubProtocol.self])
            XCTFail()
        } catch {
            XCTAssertEqual(StubProtocol.requests.count, 1)
            XCTAssertNil(StubProtocol.requests.first?.value(forHTTPHeaderField: "X-API-KEY"))
            guard case .unreachable? = error as? ProtectError else { return XCTFail("\(error)") }
        }
    }

    func testProbeRejectsInvalidHost() async {
        do { _ = try await ProtectClient.probeFingerprint(host: "  "); XCTFail() } catch {
            XCTAssertEqual(error as? ProtectError, .invalidHost)
        }
    }

    func testUnauthorized() async {
        StubProtocol.responses["GET \(base)/meta/info"] = (401, Data())
        do { _ = try await client().metaInfo(); XCTFail() } catch { XCTAssertEqual(error as? ProtectError, .unauthorized) }
    }

    func testRTSPURLUsesExistingStream() async throws {
        StubProtocol.responses["GET \(base)/cameras/c1/rtsps-stream"] = (200, try fixture("rtsps-stream"))
        let url = try await client().rtspURL(cameraId: "c1")
        XCTAssertEqual(url, "rtsp://192.168.1.1:7447/HighAlias")
        XCTAssertFalse(StubProtocol.requests.contains { $0.httpMethod == "POST" })
    }

    func testRTSPURLCreatesStreamWhenMissing() async throws {
        StubProtocol.responses["GET \(base)/cameras/c1/rtsps-stream"] = (200, try fixture("rtsps-stream-empty"))
        StubProtocol.responses["POST \(base)/cameras/c1/rtsps-stream"] = (200, Data(#"{"high":"rtsps://192.168.1.1:7441/New?enableSrtp"}"#.utf8))
        let url = try await client().rtspURL(cameraId: "c1")
        XCTAssertEqual(url, "rtsp://192.168.1.1:7447/New")
        let post = try XCTUnwrap(StubProtocol.requests.first { $0.httpMethod == "POST" })
        let body = try XCTUnwrap(post.httpBody ?? post.httpBodyStream.map { s -> Data in
            s.open(); defer { s.close() }
            var d = Data(); var buf = [UInt8](repeating: 0, count: 256)
            while s.hasBytesAvailable { let n = s.read(&buf, maxLength: 256); if n <= 0 { break }; d.append(buf, count: n) }
            return d
        })
        XCTAssertEqual(String(data: body, encoding: .utf8), #"{"qualities":["high"]}"#)
    }

    func testSnapshotReturnsImageBytesAndSendsKey() async throws {
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xD9])
        StubProtocol.responses["GET \(base)/cameras/cam1/snapshot"] = (200, jpeg)
        let data = try await client().snapshot(cameraId: "cam1")
        XCTAssertEqual(data, jpeg)
        XCTAssertEqual(StubProtocol.requests.last?.value(forHTTPHeaderField: "X-API-KEY"), "KEY")
    }

    func testSnapshotUnauthorized() async {
        StubProtocol.responses["GET \(base)/cameras/cam1/snapshot"] = (401, Data())
        do {
            _ = try await client().snapshot(cameraId: "cam1")
            XCTFail("401 must throw")
        } catch {
            XCTAssertEqual(error as? ProtectError, .unauthorized)
        }
    }
}
