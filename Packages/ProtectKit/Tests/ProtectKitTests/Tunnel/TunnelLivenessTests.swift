import XCTest
@testable import ProtectKit

final class TunnelLivenessTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testSteadyTrafficStaysUp() {
        var l = TunnelLiveness(stallAfter: 75)
        for i in 0..<20 {
            XCTAssertEqual(l.observe(rxBytes: Int64(i * 100), at: t0 + TimeInterval(i * 5)), .none)
        }
        XCTAssertFalse(l.isDown)
    }

    func testStallThenRecovery() {
        var l = TunnelLiveness(stallAfter: 75)
        XCTAssertEqual(l.observe(rxBytes: 500, at: t0), .none)
        XCTAssertEqual(l.observe(rxBytes: 500, at: t0 + 74), .none)
        XCTAssertEqual(l.observe(rxBytes: 500, at: t0 + 75), .wentDown)
        XCTAssertTrue(l.isDown)
        // An outage is reported once, not on every sample.
        XCTAssertEqual(l.observe(rxBytes: 500, at: t0 + 200), .none)
        XCTAssertEqual(l.observe(rxBytes: 700, at: t0 + 205), .recovered)
        XCTAssertFalse(l.isDown)
        XCTAssertEqual(l.observe(rxBytes: 900, at: t0 + 210), .none)
    }

    func testNeverAnsweringPeerGoesDown() {
        var l = TunnelLiveness(stallAfter: 75)
        XCTAssertEqual(l.observe(rxBytes: 0, at: t0), .none)
        XCTAssertEqual(l.observe(rxBytes: 0, at: t0 + 80), .wentDown)
    }

    func testCounterResetCountsAsTraffic() {
        var l = TunnelLiveness(stallAfter: 75)
        _ = l.observe(rxBytes: 9000, at: t0)
        XCTAssertEqual(l.observe(rxBytes: 10, at: t0 + 5), .none)
        XCTAssertFalse(l.isDown)
    }
}
