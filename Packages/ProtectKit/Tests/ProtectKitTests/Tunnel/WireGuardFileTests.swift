import XCTest
@testable import ProtectKit

final class WireGuardFileTests: XCTestCase {
    func testText() {
        XCTAssertEqual(WireGuardFile.text(from: Data("[Interface]\n".utf8)), .success("[Interface]\n"))
    }

    func testRejectsEmptyBinaryAndHuge() {
        XCTAssertEqual(WireGuardFile.text(from: Data()), .failure(.empty))
        XCTAssertEqual(WireGuardFile.text(from: Data(" \n".utf8)), .failure(.empty))
        XCTAssertEqual(WireGuardFile.text(from: Data([0x25, 0x50, 0x44, 0x46, 0xFF, 0xFE, 0x00])), .failure(.notText))
        XCTAssertEqual(WireGuardFile.text(from: Data(repeating: 0x41, count: WireGuardFile.maxBytes + 1)), .failure(.tooLarge))
    }

    func testErrorMessagesNeverEchoContent() {
        let secret = "SECRETKEYVALUE0123456789abcdefghijklmnopqrs="
        let nul = Data("PrivateKey = \(secret)\u{0}".utf8)
        guard case .failure(let problem) = WireGuardFile.text(from: nul) else { return XCTFail("expected failure") }
        XCTAssertFalse((problem.errorDescription ?? "").contains(secret))
        XCTAssertFalse("\(problem)".contains(secret))
    }
}
