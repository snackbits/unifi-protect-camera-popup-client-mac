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

    // MARK: - EventTracker (kinds arriving in updates)

    private func add(_ id: String, _ types: [String], camera: String = "c") -> Data {
        let list = types.map { "\"\($0)\"" }.joined(separator: ",")
        return msg(#"{"type":"add","item":{"id":"\#(id)","modelKey":"event","type":"smartDetectZone","start":1000,"device":"\#(camera)","smartDetectTypes":[\#(list)]}}"#)
    }

    private func update(_ id: String, _ types: [String]) -> Data {
        let list = types.map { "\"\($0)\"" }.joined(separator: ",")
        return msg(#"{"type":"update","item":{"id":"\#(id)","modelKey":"event","smartDetectTypes":[\#(list)]}}"#)
    }

    func testTrackerYieldsOnlyNewKindsFromUpdates() throws {
        var tracker = EventTracker()
        let first = try XCTUnwrap(tracker.ingest(add("e1", ["person"], camera: "cam")))
        XCTAssertEqual(first.trigger.kinds, [.person])
        XCTAssertEqual(first.previousKinds, [])
        XCTAssertNil(tracker.ingest(update("e1", ["person"])))
        let second = try XCTUnwrap(tracker.ingest(update("e1", ["person", "vehicle"])))
        XCTAssertEqual(second.trigger.kinds, [.vehicle])
        XCTAssertEqual(second.previousKinds, [.person])
        XCTAssertEqual(second.trigger.cameraId, "cam", "the camera comes from the add")
        XCTAssertEqual(second.trigger.start, Date(timeIntervalSince1970: 1))
        XCTAssertNil(tracker.ingest(update("e1", ["person", "vehicle"])))
        XCTAssertNil(tracker.ingest(update("e1", ["vehicle"])))
    }

    func testTrackerEmptyAddThenUpdate() throws {
        var tracker = EventTracker()
        XCTAssertNil(tracker.ingest(add("e1", [])))
        let tracked = try XCTUnwrap(tracker.ingest(update("e1", ["person"])))
        XCTAssertEqual(tracked.trigger.kinds, [.person])
        XCTAssertEqual(tracked.previousKinds, [])
    }

    func testTrackerIgnoresDuplicatesUnknownIdsAndOtherFrames() throws {
        var tracker = EventTracker()
        XCTAssertNotNil(tracker.ingest(msg(#"{"type":"add","item":{"id":"r1","modelKey":"event","type":"ring","start":1,"device":"door"}}"#)))
        XCTAssertNil(tracker.ingest(msg(#"{"type":"add","item":{"id":"r1","modelKey":"event","type":"ring","start":1,"device":"door"}}"#)))
        XCTAssertNil(tracker.ingest(update("unknown", ["person"])))
        XCTAssertNil(tracker.ingest(msg(#"{"type":"update","item":{"id":"r1","modelKey":"event","end":2}}"#)))
        XCTAssertNil(tracker.ingest(msg(#"{"type":"add","item":{"id":"s1","modelKey":"event","type":"sensorOpened","start":1,"device":"s"}}"#)))
        XCTAssertNil(tracker.ingest(update("s1", ["person"])), "unknown event types are not tracked")
        XCTAssertNil(tracker.ingest(msg("not json")))
        XCTAssertNil(tracker.ingest(update("e9", ["unknownThing"])))
    }

    func testTrackerIsBoundedAndEvictsOldest() throws {
        var tracker = EventTracker(capacity: 2)
        XCTAssertNil(tracker.ingest(add("a", [])))
        XCTAssertNil(tracker.ingest(add("b", [])))
        XCTAssertNil(tracker.ingest(add("c", [])))   // evicts "a"
        XCTAssertEqual(tracker.count, 2)
        XCTAssertNil(tracker.ingest(update("a", ["person"])))
        XCTAssertEqual(tracker.ingest(update("b", ["person"]))?.trigger.kinds, [.person])
        XCTAssertEqual(tracker.ingest(update("c", ["animal"]))?.trigger.kinds, [.animal])
        for i in 0..<50 { _ = tracker.ingest(add("x\(i)", ["person"])) }
        XCTAssertEqual(tracker.count, 2)
    }
}
