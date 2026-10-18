import XCTest
@testable import ProtectKit

final class TunnelPathTests: XCTestCase {
    private let lan = ["192.168.1.0/24", "fd00::/64"]

    // MARK: Webhooks

    private func webhook(_ url: String, route: ProtectRoute = .tunnel, allowed: [String]? = nil) -> TunnelPath.Webhook {
        TunnelPath.webhook(URL(string: url)!, route: route, allowedIPs: allowed ?? lan)
    }

    func testWebhookAtHomeIsAlwaysDirect() {
        XCTAssertEqual(webhook("http://192.168.1.20:8123/a", route: .direct), .direct)
        XCTAssertEqual(webhook("http://10.0.0.5/a", route: .direct), .direct)
    }

    func testWebhookInsideAllowedIPsGoesThroughForward() {
        XCTAssertEqual(webhook("http://192.168.1.20:8123/api/webhook/door?x=1"),
                       .forward(ForwardTarget(host: "192.168.1.20", port: 8123)))
    }

    func testWebhookDefaultPorts() {
        XCTAssertEqual(webhook("http://192.168.1.20/a"), .forward(ForwardTarget(host: "192.168.1.20", port: 80)))
        XCTAssertEqual(webhook("https://192.168.1.20/a"), .forward(ForwardTarget(host: "192.168.1.20", port: 443)))
    }

    func testWebhookIPv6Literal() {
        XCTAssertEqual(webhook("https://[fd00::5]:8443/hook"), .forward(ForwardTarget(host: "fd00::5", port: 8443)))
    }

    func testWebhookPrivateAddressOutsideAllowedIPsIsRefused() {
        // Away, this would reach whatever device has that address on the foreign network.
        XCTAssertEqual(webhook("http://10.0.0.5/a"), .refuse)
        XCTAssertEqual(webhook("http://172.16.4.1/a"), .refuse)
        XCTAssertEqual(webhook("http://172.31.255.1/a"), .refuse)
        XCTAssertEqual(webhook("http://192.168.2.20/a"), .refuse)
        XCTAssertEqual(webhook("http://169.254.10.1/a"), .refuse)
        XCTAssertEqual(webhook("http://[fd12::1]/a"), .refuse)
        XCTAssertEqual(webhook("http://[fe80::1]/a"), .refuse)
    }

    func testWebhookPublicAddressOrNameStaysDirect() {
        XCTAssertEqual(webhook("https://hooks.example.com/a"), .direct)
        XCTAssertEqual(webhook("http://homeassistant.local:8123/a", allowed: ["0.0.0.0/0"]), .direct)
        XCTAssertEqual(webhook("http://172.32.0.1/a"), .direct)
        XCTAssertEqual(webhook("http://8.8.8.8/a"), .direct)
        XCTAssertEqual(webhook("http://[2001:db8::1]/a"), .direct)
    }

    func testWebhookOtherSchemeStaysDirect() {
        XCTAssertEqual(webhook("ftp://192.168.1.20/a"), .direct)
    }

    func testWebhookNotRoutedText() {
        XCTAssertEqual(TunnelText.webhookNotRouted, "Button unterwegs nicht erreichbar.")
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
