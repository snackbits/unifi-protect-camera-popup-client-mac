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

    func testCandidateReachableDirectlyGoesDirect() {
        XCTAssertTrue(RouteDecision.needsCandidateProbe(mode: .automatic, hasTunnel: true, isConfiguredHost: false))
        XCTAssertEqual(RouteDecision.decideCandidate(mode: .automatic, hasTunnel: true, isConfiguredHost: false,
                                                     current: .tunnel, answered: true), .direct)
    }

    func testCandidateUnreachableUsesTunnel() {
        XCTAssertEqual(RouteDecision.decideCandidate(mode: .automatic, hasTunnel: true, isConfiguredHost: false,
                                                     current: .tunnel, answered: false), .tunnel)
        XCTAssertEqual(RouteDecision.decideCandidate(mode: .automatic, hasTunnel: true, isConfiguredHost: false,
                                                     current: .direct, answered: false), .tunnel)
    }

    func testConfiguredHostKeepsCurrentRoute() {
        XCTAssertFalse(RouteDecision.needsCandidateProbe(mode: .automatic, hasTunnel: true, isConfiguredHost: true))
        for current in [ProtectRoute.direct, .tunnel] {
            for answered in [true, false] {
                XCTAssertEqual(RouteDecision.decideCandidate(mode: .automatic, hasTunnel: true, isConfiguredHost: true,
                                                             current: current, answered: answered), current)
            }
        }
    }

    func testCandidateModeAlwaysUsesTunnel() {
        XCTAssertFalse(RouteDecision.needsCandidateProbe(mode: .always, hasTunnel: true, isConfiguredHost: false))
        XCTAssertEqual(RouteDecision.decideCandidate(mode: .always, hasTunnel: true, isConfiguredHost: false,
                                                     current: .direct, answered: true), .tunnel)
    }

    func testCandidateModeOffGoesDirect() {
        XCTAssertFalse(RouteDecision.needsCandidateProbe(mode: .off, hasTunnel: true, isConfiguredHost: false))
        XCTAssertEqual(RouteDecision.decideCandidate(mode: .off, hasTunnel: true, isConfiguredHost: false,
                                                     current: .tunnel, answered: false), .direct)
    }

    func testCandidateWithoutTunnelGoesDirect() {
        XCTAssertFalse(RouteDecision.needsCandidateProbe(mode: .automatic, hasTunnel: false, isConfiguredHost: false))
        XCTAssertEqual(RouteDecision.decideCandidate(mode: .automatic, hasTunnel: false, isConfiguredHost: false,
                                                     current: .direct, answered: false), .direct)
    }

    func testNoPinWithTunnelRequiresConfirmation() {
        // Hotel router on the home address: a direct answer is no proof of being at home.
        XCTAssertTrue(RouteDecision.requiresFingerprintConfirmation(hasTunnel: true, isConfiguredHost: false,
                                                                    pinned: nil, confirmed: false))
        XCTAssertTrue(RouteDecision.requiresFingerprintConfirmation(hasTunnel: true, isConfiguredHost: true,
                                                                    pinned: nil, confirmed: false))
        XCTAssertTrue(RouteDecision.requiresFingerprintConfirmation(hasTunnel: true, isConfiguredHost: false,
                                                                    pinned: "", confirmed: false))
        XCTAssertFalse(RouteDecision.requiresFingerprintConfirmation(hasTunnel: true, isConfiguredHost: false,
                                                                     pinned: nil, confirmed: true))
    }

    func testNoPinWithoutTunnelTrustsOnFirstUse() {
        for configured in [true, false] {
            XCTAssertFalse(RouteDecision.requiresFingerprintConfirmation(hasTunnel: false, isConfiguredHost: configured,
                                                                         pinned: nil, confirmed: false))
        }
    }

    func testPinKeepsExistingRules() {
        for hasTunnel in [true, false] {
            // Another console while one is pinned: confirm first.
            XCTAssertTrue(RouteDecision.requiresFingerprintConfirmation(hasTunnel: hasTunnel, isConfiguredHost: false,
                                                                        pinned: "AA", confirmed: false))
            // The pinned console itself: connects pinned, no alert.
            XCTAssertFalse(RouteDecision.requiresFingerprintConfirmation(hasTunnel: hasTunnel, isConfiguredHost: true,
                                                                         pinned: "AA", confirmed: false))
            XCTAssertFalse(RouteDecision.requiresFingerprintConfirmation(hasTunnel: hasTunnel, isConfiguredHost: false,
                                                                         pinned: "AA", confirmed: true))
        }
    }

    func testBackgroundConnectNeedsPinWithTunnel() {
        XCTAssertTrue(RouteDecision.requiresConfirmedPin(hasTunnel: true, pinned: nil))
        XCTAssertTrue(RouteDecision.requiresConfirmedPin(hasTunnel: true, pinned: ""))
        XCTAssertFalse(RouteDecision.requiresConfirmedPin(hasTunnel: true, pinned: "AA"))
    }

    func testBackgroundConnectWithoutTunnelTrustsOnFirstUse() {
        XCTAssertFalse(RouteDecision.requiresConfirmedPin(hasTunnel: false, pinned: nil))
        XCTAssertFalse(RouteDecision.requiresConfirmedPin(hasTunnel: false, pinned: ""))
        XCTAssertFalse(RouteDecision.requiresConfirmedPin(hasTunnel: false, pinned: "AA"))
    }

    func testModeLabels() {
        XCTAssertEqual(TunnelMode.allCases.map(\.label), ["Automatisch", "Immer", "Nie"])
    }
}
