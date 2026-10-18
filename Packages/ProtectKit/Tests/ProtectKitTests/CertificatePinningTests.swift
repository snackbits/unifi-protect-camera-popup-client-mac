import XCTest
@testable import ProtectKit

final class CertificatePinningTests: XCTestCase {
    func testFingerprintIsUppercaseColonSeparatedSHA256() {
        // SHA-256("abc")
        XCTAssertEqual(
            CertificatePinning.fingerprint(of: Data("abc".utf8)),
            "BA:78:16:BF:8F:01:CF:EA:41:41:40:DE:5D:AE:22:23:B0:03:61:A3:96:17:7A:9C:B4:10:FF:61:F2:00:15:AD"
        )
    }

    func testDecisions() {
        XCTAssertEqual(CertificatePinning.decide(presented: "AA", pinned: nil), .trustAndRemember("AA"))
        XCTAssertEqual(CertificatePinning.decide(presented: "AA", pinned: "AA"), .trust)
        XCTAssertEqual(CertificatePinning.decide(presented: "BB", pinned: "AA"), .reject)
    }
}
