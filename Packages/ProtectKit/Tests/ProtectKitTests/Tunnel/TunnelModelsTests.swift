import XCTest
@testable import ProtectKit

final class TunnelModelsTests: XCTestCase {
    func testParseValid() {
        let json = #"{"ok":true,"summary":{"endpoint":"home.example.org:51820","addresses":["192.168.3.2/32"],"allowedIPs":["0.0.0.0/0","::/0"],"dns":["192.168.3.1"],"warnings":[]}}"#
        XCTAssertEqual(TunnelParseResult.decode(json), .valid(TunnelConfigSummary(
            endpoint: "home.example.org:51820", addresses: ["192.168.3.2/32"],
            allowedIPs: ["0.0.0.0/0", "::/0"], dns: ["192.168.3.1"], warnings: [])))
    }

    func testParseInvalidCarriesGoMessage() {
        XCTAssertEqual(TunnelParseResult.decode(#"{"ok":false,"error":"Zeile 3: Address \"x\" ungültig"}"#),
                       .invalid("Zeile 3: Address \"x\" ungültig"))
    }

    func testParseGarbageIsInvalidNotCrash() {
        XCTAssertEqual(TunnelParseResult.decode("nicht json"), .invalid("Unerwartete Antwort des Tunnel-Moduls."))
    }

    func testStatusStopped() {
        XCTAssertEqual(TunnelStatus.decode(#"{"up":false}"#), .stopped)
    }

    func testStatusRunning() {
        let json = #"{"up":true,"peers":[{"publicKey":"x","endpoint":"203.0.113.5:51820","lastHandshakeUnix":1760000000,"handshakeAgeSeconds":12,"rxBytes":4096,"txBytes":2048,"keepaliveSeconds":25}],"forwardConnections":2,"forwardBytesUp":10,"forwardBytesDown":20}"#
        let s = TunnelStatus.decode(json)
        XCTAssertTrue(s.up)
        XCTAssertEqual(s.rxBytes, 4096)
        XCTAssertEqual(s.lastHandshake, Date(timeIntervalSince1970: 1_760_000_000))
    }

    func testStatusWithoutHandshake() {
        let json = #"{"up":true,"peers":[{"publicKey":"x","endpoint":"","lastHandshakeUnix":0,"handshakeAgeSeconds":-1,"rxBytes":0,"txBytes":148,"keepaliveSeconds":25}]}"#
        XCTAssertNil(TunnelStatus.decode(json).lastHandshake)
    }
}
