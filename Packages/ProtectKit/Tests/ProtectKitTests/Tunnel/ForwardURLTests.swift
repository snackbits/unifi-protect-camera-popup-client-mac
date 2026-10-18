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

    func testForwardTargetRefusesPortsOutsideRange() {
        for port in [0, -1, 65536, 5_000_000_000] {
            XCTAssertNil(ForwardTarget(host: "192.168.1.1", port: port), "port \(port)")
        }
        XCTAssertEqual(ForwardTarget(host: "192.168.1.1", port: 1)?.port, 1)
        XCTAssertEqual(ForwardTarget(host: "192.168.1.1", port: 65535)?.port, 65535)
    }

    func testForwardTargetRefusesZoneIDAndEmptyHost() {
        XCTAssertNil(ForwardTarget(host: "fe80::1%en0", port: 443))
        XCTAssertNil(ForwardTarget(host: "", port: 443))
    }

    func testAPITargetRefusesPortsOutsideRange() {
        XCTAssertNil(ForwardURL.apiTarget(consoleHost: "192.168.1.1:0"))
        XCTAssertNil(ForwardURL.apiTarget(consoleHost: "192.168.1.1:65536"))
        XCTAssertNil(ForwardURL.apiTarget(consoleHost: "192.168.1.1:5000000000"))
        XCTAssertNil(ForwardURL.apiTarget(consoleHost: "[fe80::1%25en0]:443"))
    }

    func testStreamTargetRefusesPortsOutsideRange() {
        XCTAssertNil(ForwardURL.streamTarget("rtsp://192.168.1.1:0/x"))
        XCTAssertNil(ForwardURL.streamTarget("rtsp://192.168.1.1:65536/x"))
        XCTAssertNil(ForwardURL.streamTarget("rtsp://192.168.1.1:5000000000/x"))
    }

    func testRewriteKeepsPathAndQuery() {
        XCTAssertEqual(ForwardURL.rewrite("rtsp://192.168.1.1:7447/AbCdEf?x=1", localPort: 50200),
                       "rtsp://127.0.0.1:50200/AbCdEf?x=1")
        XCTAssertEqual(ForwardURL.rewrite("rtsp://[fd00::1]:7447/A", localPort: 50201),
                       "rtsp://127.0.0.1:50201/A")
    }
}
