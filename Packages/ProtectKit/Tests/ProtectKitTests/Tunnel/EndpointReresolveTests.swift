import XCTest
@testable import ProtectKit

final class EndpointReresolveTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    /// Seconds after t0 at which a sample every 5 s triggers a lookup, up to `end`.
    private func firings(_ r: inout EndpointReresolve, handshake: Date?, from start: Int, to end: Int) -> [Int] {
        stride(from: start, through: end, by: 5).filter { s in
            r.shouldReresolve(lastHandshake: handshake, now: t0 + TimeInterval(s))
        }
    }

    func testHealthyHandshakesNeverTrigger() {
        var r = EndpointReresolve(since: t0)
        for s in stride(from: 0, through: 1000, by: 5) {
            let handshake = t0 + TimeInterval(s / 120 * 120)  // rekey every 2 min
            XCTAssertFalse(r.shouldReresolve(lastHandshake: handshake, now: t0 + TimeInterval(s)))
        }
    }

    func testStallTriggersThenBacksOffToTenMinutes() {
        var r = EndpointReresolve(since: t0)
        let handshake = t0 + 10
        // Stall at 190 s, then +60, +120, +240, +480, +600, +600.
        XCTAssertEqual(firings(&r, handshake: handshake, from: 0, to: 2500),
                       [190, 250, 370, 610, 1090, 1690, 2290])
    }

    func testNoHandshakeYetCountsFromStart() {
        var r = EndpointReresolve(since: t0)
        XCTAssertFalse(r.shouldReresolve(lastHandshake: nil, now: t0 + 179))
        XCTAssertTrue(r.shouldReresolve(lastHandshake: nil, now: t0 + 180))
        XCTAssertFalse(r.shouldReresolve(lastHandshake: nil, now: t0 + 200))
    }

    func testFreshHandshakeResetsBackoff() {
        var r = EndpointReresolve(since: t0)
        XCTAssertEqual(firings(&r, handshake: t0, from: 0, to: 400), [180, 240, 360])
        // Peer answers again at 400 s, then goes silent: first lookup at stall, then +60.
        XCTAssertFalse(r.shouldReresolve(lastHandshake: t0 + 400, now: t0 + 405))
        XCTAssertEqual(firings(&r, handshake: t0 + 400, from: 405, to: 700), [580, 640])
    }

    func testResetRestartsStallClock() {
        var r = EndpointReresolve(since: t0)
        XCTAssertEqual(firings(&r, handshake: nil, from: 0, to: 300), [180, 240])
        // Network change at 300 s re-resolved already: wait a full stall again.
        r.reset(at: t0 + 300)
        XCTAssertEqual(firings(&r, handshake: nil, from: 305, to: 560), [480, 540])
    }

    func testHostNameDetection() {
        XCTAssertTrue(EndpointReresolve.isHostName(endpoint: "home.example.org:8082"))
        XCTAssertTrue(EndpointReresolve.isHostName(endpoint: "myhome.dyndns.net:51820"))
        XCTAssertTrue(EndpointReresolve.isHostName(endpoint: "1.2.3.example.org:51820"))
        XCTAssertFalse(EndpointReresolve.isHostName(endpoint: "203.0.113.7:51820"))
        XCTAssertFalse(EndpointReresolve.isHostName(endpoint: "[2001:db8::1]:51820"))
        XCTAssertFalse(EndpointReresolve.isHostName(endpoint: ""))
    }

    func testDecodeResult() {
        let ok = TunnelReresolveResult.decode(#"{"updates":[{"host":"home.example.org","ip":"203.0.113.9","changed":true}]}"#)
        XCTAssertEqual(ok, TunnelReresolveResult(
            updates: [.init(host: "home.example.org", ip: "203.0.113.9", changed: true)], error: nil))
        let failed = TunnelReresolveResult.decode(#"{"error":"Endpoint nicht auflösbar","updates":[]}"#)
        XCTAssertEqual(failed.error, "Endpoint nicht auflösbar")
        XCTAssertNotNil(TunnelReresolveResult.decode("kaputt").error)
    }
}
