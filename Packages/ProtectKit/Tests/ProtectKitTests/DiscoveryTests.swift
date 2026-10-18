import XCTest
@testable import ProtectKit

final class DiscoveryTests: XCTestCase {
    private func tlv(_ type: UInt8, _ value: [UInt8]) -> [UInt8] {
        [type, UInt8(value.count >> 8), UInt8(value.count & 0xFF)] + value
    }

    func testRequestBytes() {
        XCTAssertEqual(DiscoveryPacket.request, [0x01, 0x00, 0x00, 0x00])
    }

    func testParsesResponse() throws {
        let body = tlv(0x02, [0xAA, 0xBB, 0xCC, 0x00, 0x00, 0x01, 192, 168, 1, 1])
            + tlv(0x0B, Array("UDM-Pro".utf8))
            + tlv(0x0C, Array("UDMPRO".utf8))
            + tlv(0x15, Array("UniFi Dream Machine Pro".utf8))
            + tlv(0x7E, [1, 2, 3])
        let packet: [UInt8] = [0x01, 0x00, UInt8(body.count >> 8), UInt8(body.count & 0xFF)] + body

        let c = try XCTUnwrap(DiscoveryPacket.parse(packet, sourceIP: "192.168.1.1"))
        XCTAssertEqual(c.ip, "192.168.1.1")
        XCTAssertEqual(c.mac, "aa:bb:cc:00:00:01")
        XCTAssertEqual(c.hostname, "UDM-Pro")
        XCTAssertEqual(c.model, "UniFi Dream Machine Pro")
        XCTAssertEqual(c.displayName, "UniFi Dream Machine Pro")
    }

    func testRejectsOwnRequestAndTruncatedPackets() {
        XCTAssertNil(DiscoveryPacket.parse([0x01, 0x00, 0x00, 0x00], sourceIP: "1.2.3.4"))
        XCTAssertNil(DiscoveryPacket.parse([0x01, 0x00, 0x00, 0x09, 0x0B, 0x00, 0x05, 0x41], sourceIP: "1.2.3.4"))
        XCTAssertNil(DiscoveryPacket.parse([0x02, 0x00, 0x00, 0x00], sourceIP: "1.2.3.4"))
    }

    func testDisplayNameFallsBackToHostnameThenIP() {
        XCTAssertEqual(DiscoveredConsole(ip: "10.0.0.1", mac: nil, hostname: "ck", model: nil).displayName, "ck")
        XCTAssertEqual(DiscoveredConsole(ip: "10.0.0.1", mac: nil, hostname: nil, model: nil).displayName, "10.0.0.1")
    }
}
