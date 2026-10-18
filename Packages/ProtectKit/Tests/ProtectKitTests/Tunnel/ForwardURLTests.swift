import XCTest
@testable import ProtectKit

final class ForwardURLTests: XCTestCase {
    func testAPITarget() {
        XCTAssertEqual(ForwardURL.apiTarget(consoleHost: "192.168.1.1"), ForwardTarget(host: "192.168.1.1", port: 443))
        XCTAssertEqual(ForwardURL.apiTarget(consoleHost: "konsole.local:8443"), ForwardTarget(host: "konsole.local", port: 8443))
        XCTAssertEqual(ForwardURL.apiTarget(consoleHost: "[fd00::1]:8443"), ForwardTarget(host: "fd00::1", port: 8443))
        XCTAssertNil(ForwardURL.apiTarget(consoleHost: " "))
    }

    func testLocalHostIsAValidConsoleHost() {
        let host = ForwardURL.localHost(port: 50123)
        XCTAssertEqual(host, "127.0.0.1:50123")
        XCTAssertEqual(ProtectClient.baseURL(for: host)?.absoluteString,
                       "https://127.0.0.1:50123/proxy/protect/integration")
    }

    func testStreamTarget() {
        XCTAssertEqual(ForwardURL.streamTarget("rtsp://192.168.1.1:7447/AbCdEf"), ForwardTarget(host: "192.168.1.1", port: 7447))
        XCTAssertEqual(ForwardURL.streamTarget("rtsp://cam.local/x"), ForwardTarget(host: "cam.local", port: 554))
        XCTAssertNil(ForwardURL.streamTarget("https://192.168.1.1/x"))
        XCTAssertNil(ForwardURL.streamTarget("kein url"))
    }

    func testRewriteKeepsPathAndQuery() {
        XCTAssertEqual(ForwardURL.rewrite("rtsp://192.168.1.1:7447/AbCdEf?x=1", localPort: 50200),
                       "rtsp://127.0.0.1:50200/AbCdEf?x=1")
        XCTAssertEqual(ForwardURL.rewrite("rtsp://[fd00::1]:7447/A", localPort: 50201),
                       "rtsp://127.0.0.1:50201/A")
    }
}
