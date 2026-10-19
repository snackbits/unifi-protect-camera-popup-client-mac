import XCTest
@testable import ProtectKit

final class TunnelTextTests: XCTestCase {
    func testLastConnection() {
        XCTAssertEqual(TunnelText.lastConnection(dayAndTime: "gestern, 18:22", via: .cellular),
                       "gestern, 18:22 · über Mobilfunk")
        XCTAssertEqual(TunnelText.lastConnection(dayAndTime: "heute, 08:05", via: .wifi), "heute, 08:05 · über WLAN")
        XCTAssertEqual(TunnelText.lastConnection(dayAndTime: "12.10., 18:22", via: .other), "12.10., 18:22 · über Netzwerk")
    }

    func testConnectedChip() {
        XCTAssertEqual(TunnelText.connectedChip(viaTunnel: false), "Zu Hause")
        XCTAssertEqual(TunnelText.connectedChip(viaTunnel: true), "Unterwegs")
    }

    func testHomeStatusMatchesTemplate() {
        let s = TunnelText.status(.home)
        XCTAssertEqual(s.title, "Bereit · gerade zu Hause")
        XCTAssertEqual(s.subtitle, "Der Tunnel springt an, sobald die Konsole nicht direkt erreichbar ist.")
    }

    func testFailedShowsMessage() {
        XCTAssertEqual(TunnelText.status(.failed("Endpoint nicht auflösbar")).subtitle, "Endpoint nicht auflösbar")
    }

    func testPhaseMapping() {
        XCTAssertEqual(TunnelPhase.from(mode: .off, route: .direct, state: .up), .off)
        XCTAssertEqual(TunnelPhase.from(mode: .automatic, route: .direct, state: .stopped), .home)
        XCTAssertEqual(TunnelPhase.from(mode: .automatic, route: .tunnel, state: .starting), .connecting)
        XCTAssertEqual(TunnelPhase.from(mode: .automatic, route: .tunnel, state: .up), .connected)
        XCTAssertEqual(TunnelPhase.from(mode: .always, route: .tunnel, state: .down), .down)
        // A tunnel that is wanted but fails to start shows why, even while the route fell back to direct.
        XCTAssertEqual(TunnelPhase.from(mode: .automatic, route: .direct, state: .failed("DNS")), .failed("DNS"))
    }

    func testTestOutcomeMessages() {
        XCTAssertEqual(TunnelTestOutcome.noHandshake(endpoint: "home.example.org:51820").message,
                       "Keine Antwort von home.example.org:51820. Prüfe Adresse und Port-Weiterleitung.")
        XCTAssertEqual(TunnelTestOutcome.ok.message, "Tunnel funktioniert – deine Konsole antwortet.")
    }
}
