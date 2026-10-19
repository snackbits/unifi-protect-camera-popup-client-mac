import XCTest
@testable import ProtectKit

final class AllowedIPsTests: XCTestCase {
    func testIPv4() {
        XCTAssertEqual(AllowedIPs.covers(host: "192.168.1.1", prefixes: ["192.168.1.0/24"]), true)
        XCTAssertEqual(AllowedIPs.covers(host: "192.168.2.1", prefixes: ["192.168.1.0/24"]), false)
        XCTAssertEqual(AllowedIPs.covers(host: "10.1.2.3", prefixes: ["0.0.0.0/0"]), true)
        XCTAssertEqual(AllowedIPs.covers(host: "192.168.1.7", prefixes: ["192.168.1.7/32"]), true)
        XCTAssertEqual(AllowedIPs.covers(host: "192.168.1.1", prefixes: ["10.0.0.0/8", "192.168.0.0/16"]), true)
    }

    func testIPv6AndFamilyMismatch() {
        XCTAssertEqual(AllowedIPs.covers(host: "fd00::1", prefixes: ["::/0"]), true)
        XCTAssertEqual(AllowedIPs.covers(host: "fd00::1", prefixes: ["0.0.0.0/0"]), false)
        XCTAssertEqual(AllowedIPs.covers(host: "192.168.1.1", prefixes: ["::/0"]), false)
    }

    func testHostNameIsUnknown() {
        XCTAssertNil(AllowedIPs.covers(host: "konsole.local", prefixes: ["0.0.0.0/0"]))
    }

    func testZoneIDIsNeverCovered() {
        XCTAssertEqual(AllowedIPs.covers(host: "fe80::1%en0", prefixes: ["::/0", "fe80::/10"]), false)
        XCTAssertEqual(AllowedIPs.covers(host: "fd00::1%lo0", prefixes: ["fd00::/64"]), false)
        XCTAssertEqual(AllowedIPs.covers(host: "fe80::1", prefixes: ["fe80::%en0/10"]), false)
    }

    func testBrokenPrefixIsIgnored() {
        XCTAssertEqual(AllowedIPs.covers(host: "192.168.1.1", prefixes: ["192.168.1.0/99", "x/8"]), false)
    }
}
