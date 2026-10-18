import XCTest
@testable import ProtectKit

final class StreamURLTests: XCTestCase {
    func testConvertsProtectRTSPSURL() {
        XCTAssertEqual(
            StreamURL.normalizedRTSP("rtsps://192.168.1.1:7441/AbCdEf123?enableSrtp"),
            "rtsp://192.168.1.1:7447/AbCdEf123"
        )
    }

    func testKeepsOtherQueryParameters() {
        XCTAssertEqual(
            StreamURL.normalizedRTSP("rtsps://h:7441/A?enableSrtp&foo=1"),
            "rtsp://h:7447/A?foo=1"
        )
    }

    func testIsIdempotent() {
        let once = StreamURL.normalizedRTSP("rtsps://h:7441/A?enableSrtp")
        XCTAssertEqual(StreamURL.normalizedRTSP(once), once)
    }

    func testLeavesPlainRTSPUntouched() {
        XCTAssertEqual(StreamURL.normalizedRTSP("rtsp://u:p@h:7447/A"), "rtsp://u:p@h:7447/A")
    }
}
