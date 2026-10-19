import XCTest
@testable import ProtectKit

final class RouteHysteresisTests: XCTestCase {
    func testSingleDeviatingResultDoesNotSwitch() {
        var filter = RouteHysteresis()
        XCTAssertNil(filter.feed(.tunnel, current: .direct))
        XCTAssertEqual(filter.candidate, .tunnel)
    }

    func testTwoConsecutiveResultsSwitch() {
        var filter = RouteHysteresis()
        XCTAssertNil(filter.feed(.tunnel, current: .direct))
        XCTAssertEqual(filter.feed(.tunnel, current: .direct), .tunnel)
        XCTAssertNil(filter.candidate)
    }

    func testAgreeingResultClearsCandidate() {
        var filter = RouteHysteresis()
        XCTAssertNil(filter.feed(.tunnel, current: .direct))
        XCTAssertNil(filter.feed(.direct, current: .direct))
        XCTAssertNil(filter.candidate)
        // Starts counting from scratch afterwards.
        XCTAssertNil(filter.feed(.tunnel, current: .direct))
        XCTAssertEqual(filter.feed(.tunnel, current: .direct), .tunnel)
    }

    func testBackHomeNeedsTwoResultsToo() {
        var filter = RouteHysteresis()
        XCTAssertNil(filter.feed(.direct, current: .tunnel))
        XCTAssertEqual(filter.feed(.direct, current: .tunnel), .direct)
    }

    func testResetForgetsCandidate() {
        var filter = RouteHysteresis()
        XCTAssertNil(filter.feed(.tunnel, current: .direct))
        filter.reset()
        XCTAssertNil(filter.candidate)
        XCTAssertNil(filter.feed(.tunnel, current: .direct))
    }

    func testRequiredOneSwitchesAtOnce() {
        var filter = RouteHysteresis(required: 1)
        XCTAssertEqual(filter.feed(.tunnel, current: .direct), .tunnel)
    }
}
