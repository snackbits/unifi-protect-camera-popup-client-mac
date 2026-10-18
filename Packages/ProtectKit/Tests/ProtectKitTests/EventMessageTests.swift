import XCTest
@testable import ProtectKit

final class EventMessageTests: XCTestCase {
    private func msg(_ json: String) -> Data { Data(json.utf8) }

    func testRingAdd() throws {
        let t = try XCTUnwrap(EventMessage.parse(msg(#"{"type":"add","item":{"id":"e1","modelKey":"event","type":"ring","start":1760780000000,"device":"cam-door"}}"#)))
        XCTAssertEqual(t.eventId, "e1")
        XCTAssertEqual(t.cameraId, "cam-door")
        XCTAssertEqual(t.kinds, [.ring])
        XCTAssertEqual(t.start, Date(timeIntervalSince1970: 1_760_780_000))
    }

    func testSmartDetectZoneUsesSmartTypes() throws {
        let t = try XCTUnwrap(EventMessage.parse(msg(#"{"type":"add","item":{"id":"e2","modelKey":"event","type":"smartDetectZone","start":1,"device":"c","smartDetectTypes":["person","vehicle"]}}"#)))
        XCTAssertEqual(t.kinds, [.person, .vehicle])
    }

    func testSmartDetectLineAndAudio() throws {
        XCTAssertEqual(EventMessage.parse(msg(#"{"type":"add","item":{"id":"e3","modelKey":"event","type":"smartDetectLine","start":1,"device":"c","smartDetectTypes":["animal"]}}"#))?.kinds, [.animal])
        XCTAssertEqual(EventMessage.parse(msg(#"{"type":"add","item":{"id":"e4","modelKey":"event","type":"smartAudioDetect","start":1,"device":"c","smartDetectTypes":["alrmSpeak"]}}"#))?.kinds, [.speak])
    }

    func testMotion() {
        XCTAssertEqual(EventMessage.parse(msg(#"{"type":"add","item":{"id":"e5","modelKey":"event","type":"motion","start":1,"device":"c"}}"#))?.kinds, [.motion])
    }

    func testIgnoresUpdatesUnknownTypesAndGarbage() {
        XCTAssertNil(EventMessage.parse(msg(#"{"type":"update","item":{"id":"e1","modelKey":"event","end":2}}"#)))
        XCTAssertNil(EventMessage.parse(msg(#"{"type":"add","item":{"id":"e6","modelKey":"event","type":"sensorOpened","start":1,"device":"s"}}"#)))
        XCTAssertNil(EventMessage.parse(msg(#"{"type":"add","item":{"id":"e7","modelKey":"event","type":"smartDetectZone","start":1,"device":"c","smartDetectTypes":["unknownThing"]}}"#)))
        XCTAssertNil(EventMessage.parse(msg(#"{"type":"add","item":{"id":"e8","modelKey":"event","type":"ring","start":1}}"#)))
        XCTAssertNil(EventMessage.parse(msg("not json")))
    }

    func testDeduplicatorRemembersRecentIds() {
        var d = EventDeduplicator(capacity: 3)
        XCTAssertTrue(d.isNew("a"))
        XCTAssertFalse(d.isNew("a"))
        XCTAssertTrue(d.isNew("b"))
        XCTAssertTrue(d.isNew("c"))
        XCTAssertTrue(d.isNew("d"))   // evicts "a"
        XCTAssertTrue(d.isNew("a"))
    }
}
