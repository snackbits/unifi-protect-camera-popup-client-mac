import XCTest
@testable import ProtectKit

final class BackoffTests: XCTestCase {
    func testDoublesUpToMaxAndResets() {
        var b = Backoff(base: 2, max: 30)
        XCTAssertEqual([b.next(), b.next(), b.next(), b.next(), b.next(), b.next()], [2, 4, 8, 16, 30, 30])
        b.reset()
        XCTAssertEqual(b.next(), 2)
    }
}
