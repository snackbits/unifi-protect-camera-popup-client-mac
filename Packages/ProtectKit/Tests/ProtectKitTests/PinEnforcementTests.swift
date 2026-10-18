import XCTest
@testable import ProtectKit

final class FailingProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.serverCertificateUntrusted)) }
    override func stopLoading() {}
}

final class PinEnforcementTests: XCTestCase {
    private func der(_ name: String) throws -> Data { try fixtureData(name, ext: "der") }

    private func trust(_ der: Data) throws -> SecTrust {
        let cert = try XCTUnwrap(SecCertificateCreateWithData(nil, der as CFData))
        var t: SecTrust?
        XCTAssertEqual(SecTrustCreateWithCertificates(cert, SecPolicyCreateBasicX509(), &t), errSecSuccess)
        return try XCTUnwrap(t)
    }

    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []
        func add(_ s: String) { lock.withLock { items.append(s) } }
        var all: [String] { lock.withLock { items } }
    }

    private func client(pinned: String?, recorder: Recorder, protocols: [AnyClass] = [FailingProtocol.self]) -> ProtectClient {
        ProtectClient(host: "192.168.1.1", apiKey: "K", pinnedFingerprint: pinned,
                      onNewFingerprint: { recorder.add($0) }, protocolClasses: protocols)
    }

    func testNoPinTrustsAndReportsFingerprintOnce() throws {
        let data = try der("selfsigned"); let rec = Recorder()
        let c = client(pinned: nil, recorder: rec)
        let (d1, cred) = c.evaluate(trust: try trust(data))
        XCTAssertEqual(d1, .useCredential); XCTAssertNotNil(cred)
        XCTAssertEqual(rec.all, [CertificatePinning.fingerprint(of: data)])
        // now remembered: a second pass trusts without another callback
        XCTAssertEqual(c.evaluate(trust: try trust(data)).0, .useCredential)
        XCTAssertEqual(rec.all.count, 1)
    }

    func testMatchingPinTrustsWithoutCallback() throws {
        let data = try der("selfsigned"); let rec = Recorder()
        let c = client(pinned: CertificatePinning.fingerprint(of: data), recorder: rec)
        XCTAssertEqual(c.evaluate(trust: try trust(data)).0, .useCredential)
        XCTAssertTrue(rec.all.isEmpty)
    }

    func testDifferentPinCancelsAndRequestReportsCertificateChanged() async throws {
        let rec = Recorder()
        let c = client(pinned: CertificatePinning.fingerprint(of: try der("selfsigned")), recorder: rec)
        let (d, cred) = c.evaluate(trust: try trust(try der("selfsigned2")))
        XCTAssertEqual(d, .cancelAuthenticationChallenge); XCTAssertNil(cred)
        XCTAssertTrue(rec.all.isEmpty)
        do { _ = try await c.metaInfo(); XCTFail() } catch { XCTAssertEqual(error as? ProtectError, .certificateChanged) }
    }

    func testRequestFailsAfterInvalidate() async {
        let c = client(pinned: nil, recorder: Recorder(), protocols: [StubProtocol.self])
        c.invalidate()
        do { _ = try await c.metaInfo(); XCTFail() } catch {
            guard case .unreachable = error as? ProtectError else { return XCTFail("\(error)") }
        }
    }
}

private func fixtureData(_ name: String, ext: String) throws -> Data {
    let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}
