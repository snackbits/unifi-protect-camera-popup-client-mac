import XCTest
@testable import ProtectKit

func fixture(_ name: String) throws -> Data {
    let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

final class ModelsTests: XCTestCase {
    func testDecodesCameras() throws {
        let cams = try JSONDecoder().decode([ProtectCamera].self, from: fixture("cameras"))
        XCTAssertEqual(cams.count, 3)

        let door = cams[0]
        XCTAssertEqual(door.id, "cam-door")
        XCTAssertEqual(door.name, "Haustür")
        XCTAssertEqual(door.modelName, "G4 Doorbell Pro")
        XCTAssertTrue(door.isConnected)
        XCTAssertTrue(door.hasSpeaker)
        XCTAssertEqual(door.supportedTriggers, [.ring, .motion, .person, .package, .vehicle, .speak, .personLine, .vehicleLine])
        XCTAssertEqual(door.enabledTriggers, [.ring, .motion, .person, .package, .personLine])

        let drive = cams[1]
        XCTAssertFalse(drive.hasSpeaker)
        XCTAssertEqual(drive.supportedTriggers, [.motion, .person, .vehicle, .licensePlate, .personLine, .vehicleLine])
        XCTAssertFalse(drive.supportedTriggers.contains(.ring))

        let old = cams[2]
        XCTAssertEqual(old.name, "Kamera AABBCC000003")
        XCTAssertFalse(old.isConnected)
        XCTAssertEqual(old.supportedTriggers, [.motion])
    }

    func testNullLcdMessageIsNotADoorbell() throws {
        let json = #"[{"id":"cam-bullet","name":"Garten","type":"G4 Bullet","state":"CONNECTED","lcdMessage":null,"featureFlags":{}}]"#
        let cam = try XCTUnwrap(try JSONDecoder().decode([ProtectCamera].self, from: Data(json.utf8)).first)
        XCTAssertFalse(cam.supportedTriggers.contains(.ring))
        XCTAssertFalse(cam.enabledTriggers.contains(.ring))
    }

    func testDecodesStreamsAndPrefersHigh() throws {
        let s = try JSONDecoder().decode(RTSPSStreams.self, from: fixture("rtsps-stream"))
        XCTAssertEqual(s.preferred, "rtsps://192.168.1.1:7441/HighAlias?enableSrtp")
        let empty = try JSONDecoder().decode(RTSPSStreams.self, from: fixture("rtsps-stream-empty"))
        XCTAssertNil(empty.preferred)
    }

    func testPreferredFallsBackToMediumThenLow() throws {
        let s = try JSONDecoder().decode(RTSPSStreams.self, from: Data(#"{"high":null,"low":"rtsps://h:7441/L?enableSrtp"}"#.utf8))
        XCTAssertEqual(s.preferred, "rtsps://h:7441/L?enableSrtp")
    }

    func testDecodesMetaInfo() throws {
        XCTAssertEqual(try JSONDecoder().decode(ProtectMetaInfo.self, from: fixture("meta-info")).applicationVersion, "6.1.79")
    }
}
