import XCTest
@testable import ProtectKit

final class TunnelPathTests: XCTestCase {
    private let lan = ["192.168.1.0/24", "fd00::/64"]

    // MARK: Webhooks

    func testWebhookInsideAllowedIPsGoesThroughForward() {
        let url = URL(string: "http://192.168.1.20:8123/api/webhook/door?x=1")!
        XCTAssertEqual(TunnelPath.webhookTarget(url, allowedIPs: lan), ForwardTarget(host: "192.168.1.20", port: 8123))
    }

    func testWebhookDefaultPorts() {
        XCTAssertEqual(TunnelPath.webhookTarget(URL(string: "http://192.168.1.20/a")!, allowedIPs: lan),
                       ForwardTarget(host: "192.168.1.20", port: 80))
        XCTAssertEqual(TunnelPath.webhookTarget(URL(string: "https://192.168.1.20/a")!, allowedIPs: lan),
                       ForwardTarget(host: "192.168.1.20", port: 443))
    }

    func testWebhookIPv6Literal() {
        let url = URL(string: "https://[fd00::5]:8443/hook")!
        XCTAssertEqual(TunnelPath.webhookTarget(url, allowedIPs: lan), ForwardTarget(host: "fd00::5", port: 8443))
    }

    func testWebhookOutsideAllowedIPsOrNameStaysDirect() {
        XCTAssertNil(TunnelPath.webhookTarget(URL(string: "http://10.0.0.5/a")!, allowedIPs: lan))
        XCTAssertNil(TunnelPath.webhookTarget(URL(string: "https://hooks.example.com/a")!, allowedIPs: lan))
        XCTAssertNil(TunnelPath.webhookTarget(URL(string: "http://homeassistant.local:8123/a")!, allowedIPs: ["0.0.0.0/0"]))
    }

    func testWebhookOtherSchemeStaysDirect() {
        XCTAssertNil(TunnelPath.webhookTarget(URL(string: "ftp://192.168.1.20/a")!, allowedIPs: lan))
    }

    func testWebhookRewriteKeepsPathAndQuery() {
        let url = URL(string: "https://192.168.1.20:8443/api/hook?token=a&b=2")!
        XCTAssertEqual(TunnelPath.rewrite(url, localPort: 50001)?.absoluteString,
                       "https://127.0.0.1:50001/api/hook?token=a&b=2")
    }

    // MARK: Talkback

    func testTalkbackDirectAtHome() {
        XCTAssertEqual(TunnelPath.talkback(host: "192.168.1.30", port: 7004, route: .direct, allowedIPs: lan), .direct)
        XCTAssertEqual(TunnelPath.talkback(host: "10.9.9.9", port: 7004, route: .direct, allowedIPs: lan), .direct)
    }

    func testTalkbackAwayInsideAllowedIPsUsesUDPForward() {
        XCTAssertEqual(TunnelPath.talkback(host: "192.168.1.30", port: 7004, route: .tunnel, allowedIPs: lan),
                       .forward(ip: "192.168.1.30", port: 7004))
        XCTAssertEqual(TunnelPath.talkback(host: "[fd00::30]", port: 7004, route: .tunnel, allowedIPs: lan),
                       .forward(ip: "fd00::30", port: 7004))
    }

    func testTalkbackAwayOutsideAllowedIPsOrNameIsNotRouted() {
        XCTAssertEqual(TunnelPath.talkback(host: "10.9.9.9", port: 7004, route: .tunnel, allowedIPs: lan), .notRouted)
        XCTAssertEqual(TunnelPath.talkback(host: "cam.local", port: 7004, route: .tunnel, allowedIPs: ["0.0.0.0/0"]), .notRouted)
    }

    func testTalkbackNotRoutedText() {
        XCTAssertEqual(TunnelText.talkbackNotRouted, "Sprechen unterwegs nicht möglich (Kamera nicht im Tunnel).")
    }
}
