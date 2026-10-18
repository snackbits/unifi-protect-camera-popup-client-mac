import XCTest
@testable import ProtectKit

final class TunnelRoutingTests: XCTestCase {
    func testWithoutTunnelAlwaysDirect() {
        for mode in TunnelMode.allCases {
            XCTAssertEqual(RouteDecision.decide(mode: mode, hasTunnel: false, direct: .unreachable), .direct)
            XCTAssertFalse(RouteDecision.needsProbe(mode: mode, hasTunnel: false))
        }
    }

    func testAutomatic() {
        XCTAssertTrue(RouteDecision.needsProbe(mode: .automatic, hasTunnel: true))
        XCTAssertEqual(RouteDecision.decide(mode: .automatic, hasTunnel: true, direct: .console), .direct)
        XCTAssertEqual(RouteDecision.decide(mode: .automatic, hasTunnel: true, direct: .unreachable), .tunnel)
    }

    func testForeignDeviceOnSameAddressUsesTunnel() {
        XCTAssertEqual(RouteDecision.decide(mode: .automatic, hasTunnel: true, direct: .otherDevice), .tunnel)
    }

    func testAlwaysAndOff() {
        XCTAssertEqual(RouteDecision.decide(mode: .always, hasTunnel: true, direct: .console), .tunnel)
        XCTAssertEqual(RouteDecision.decide(mode: .off, hasTunnel: true, direct: .unreachable), .direct)
        XCTAssertFalse(RouteDecision.needsProbe(mode: .always, hasTunnel: true))
    }

    func testReachabilityFromPin() {
        XCTAssertEqual(DirectReachability.from(presentedFingerprint: nil, pinned: "AA"), .unreachable)
        XCTAssertEqual(DirectReachability.from(presentedFingerprint: "AA", pinned: nil), .console)
        XCTAssertEqual(DirectReachability.from(presentedFingerprint: "AA", pinned: ""), .console)
        XCTAssertEqual(DirectReachability.from(presentedFingerprint: "AA", pinned: "AA"), .console)
        XCTAssertEqual(DirectReachability.from(presentedFingerprint: "BB", pinned: "AA"), .otherDevice)
    }

    func testModeLabels() {
        XCTAssertEqual(TunnelMode.allCases.map(\.label), ["Automatisch", "Immer", "Nie"])
    }
}
