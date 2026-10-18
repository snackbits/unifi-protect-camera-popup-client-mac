import XCTest
@testable import ProtectKit

/// Serves canned responses keyed by "METHOD path".
final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var responses: [String: (Int, Data)] = [:]
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        let key = "\(request.httpMethod ?? "GET") \(request.url?.path ?? "")"
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

    func testSendsApiKeyAndDecodesCameras() async throws {
        StubProtocol.responses["GET \(base)/cameras"] = (200, try fixture("cameras"))
        let cams = try await client().cameras()
        XCTAssertEqual(cams.map(\.id), ["cam-door", "cam-drive", "cam-old"])
        XCTAssertEqual(StubProtocol.requests.first?.value(forHTTPHeaderField: "X-API-KEY"), "KEY")
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
}
