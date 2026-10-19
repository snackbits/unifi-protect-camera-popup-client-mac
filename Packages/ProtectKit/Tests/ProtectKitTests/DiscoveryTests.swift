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

    func testProbeAcceptsConsoleSystemInfo() throws {
        let json = Data(#"{"hardware":{"shortname":"UDMPROSE"},"name":"snackbits","mac":"70A741B5EF8D"}"#.utf8)
        let candidate = DiscoveredConsole(ip: "172.2.4.1", mac: nil, hostname: nil, model: nil)
        let c = try XCTUnwrap(ConsoleProbe.parse(json, candidate: candidate))
        XCTAssertEqual(c.displayName, "snackbits (UDMPROSE)")
        XCTAssertEqual(c.mac, "70:a7:41:b5:ef:8d")
        XCTAssertEqual(c.ip, "172.2.4.1")
    }

    func testProbeRejectsNonConsoleAnswers() {
        let candidate = DiscoveredConsole(ip: "1.2.3.4", mac: nil, hostname: "SchuppenFeld", model: "Unifi-Protect-UAP-Bridge")
        XCTAssertNil(ConsoleProbe.parse(Data("<html></html>".utf8), candidate: candidate))
        XCTAssertNil(ConsoleProbe.parse(Data(#"{"name":"x"}"#.utf8), candidate: candidate))
    }

    func testProbeFallsBackToProtectEndpointWhenSystemNeedsLogin() throws {
        let candidate = DiscoveredConsole(ip: "10.0.0.1", mac: "aa:bb:cc:00:00:01", hostname: "UDM", model: nil)
        let console = try XCTUnwrap(ConsoleProbe.decide(systemStatus: 401, systemData: Data(), metaStatus: 401, candidate: candidate))
        XCTAssertEqual(console.ip, "10.0.0.1")
        XCTAssertEqual(console.displayName, "UDM")
        XCTAssertNotNil(ConsoleProbe.decide(systemStatus: 403, systemData: nil, metaStatus: 401, candidate: candidate))
    }

    func testProbeFallbackNeedsBothSignals() {
        let candidate = DiscoveredConsole(ip: "10.0.0.2", mac: nil, hostname: nil, model: "UVC G4 Bullet")
        XCTAssertNil(ConsoleProbe.decide(systemStatus: 401, systemData: Data(), metaStatus: 404, candidate: candidate))
        XCTAssertNil(ConsoleProbe.decide(systemStatus: 404, systemData: nil, metaStatus: 401, candidate: candidate))
        XCTAssertNil(ConsoleProbe.decide(systemStatus: 401, systemData: nil, metaStatus: nil, candidate: candidate))
        XCTAssertNil(ConsoleProbe.decide(systemStatus: nil, systemData: nil, metaStatus: nil, candidate: candidate))
    }

    func testProbeStillParsesSystemInfo() throws {
        let json = Data(#"{"hardware":{"shortname":"UDMPROSE"},"name":"snackbits","mac":"70A741B5EF8D"}"#.utf8)
        let candidate = DiscoveredConsole(ip: "172.2.4.1", mac: nil, hostname: nil, model: nil)
        let console = try XCTUnwrap(ConsoleProbe.decide(systemStatus: 200, systemData: json, metaStatus: nil, candidate: candidate))
        XCTAssertEqual(console.displayName, "snackbits (UDMPROSE)")
    }
}
