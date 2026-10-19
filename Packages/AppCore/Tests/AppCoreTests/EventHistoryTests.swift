import XCTest
@testable import AppCore

final class EventHistoryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func record(_ entry: String, _ offset: TimeInterval, kind: String? = "Person") -> EventRecord {
        EventRecord(entryId: entry, kindLabel: kind, cameraName: "Haustür", date: now.addingTimeInterval(offset))
    }

    func testNewestFirstAndCapped() {
        var history = EventHistory()
        for index in 0..<25 { history.record(record("A", Double(index))) }
        XCTAssertEqual(history.records.count, EventHistory.capacity)
        XCTAssertEqual(history.latest(3).map(\.date), [24, 23, 22].map { now.addingTimeInterval($0) })
        XCTAssertEqual(history.latest(0), [])
    }

    func testOutOfOrderEventIsSortedIn() {
        var history = EventHistory()
        history.record(record("A", 10))
        history.record(record("B", 5))
        history.record(record("C", 20))
        XCTAssertEqual(history.records.map(\.entryId), ["C", "A", "B"])
    }

    func testLastTriggeredPerCamera() {
        var history = EventHistory()
        history.record(record("A", 10))
        history.record(record("B", 20))
        XCTAssertEqual(history.lastTriggered(entry: "A"), now.addingTimeInterval(10))
        XCTAssertNil(history.lastTriggered(entry: "C"))
    }

    // Review Focus 3
    func testRemoveEntries() {
        var history = EventHistory()
        history.record(record("A", 10))
        history.record(record("B", 20))
        history.removeEntries(notIn: ["B"])
        XCTAssertEqual(history.records.map(\.entryId), ["B"])
    }

    func testTitleFallsBackToWebhook() {
        XCTAssertEqual(record("A", 0, kind: "Klingel").title, "Klingel")
        XCTAssertEqual(record("A", 0, kind: nil).title, "Webhook")
    }

    func testCodableRoundTripAndLenientDecode() throws {
        var history = EventHistory()
        history.record(record("A", 10))
        let decoded = try JSONDecoder().decode(EventHistory.self, from: JSONEncoder().encode(history))
        XCTAssertEqual(decoded, history)
        let broken = try JSONDecoder().decode(EventHistory.self, from: Data(#"{"records":"x"}"#.utf8))
        XCTAssertEqual(broken, EventHistory())
    }
}
