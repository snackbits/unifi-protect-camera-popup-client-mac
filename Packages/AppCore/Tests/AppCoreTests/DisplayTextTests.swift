import XCTest
@testable import AppCore

final class DisplayTextTests: XCTestCase {
    private let tz = TimeZone(identifier: "Europe/Berlin")!

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    func testPopupChip() {
        let at = date("2026-10-18T10:41:00+02:00")
        XCTAssertEqual(DisplayText.popupChip(kind: "Klingel", camera: "Haustür", date: at, timeZone: tz), "Klingel · Haustür · 10:41")
    }

    // Review Focus 5
    func testPopupChipWithoutKindOrName() {
        let at = date("2026-10-18T10:41:00+02:00")
        XCTAssertEqual(DisplayText.popupChip(kind: nil, camera: "Haustür", date: at, timeZone: tz), "Haustür · 10:41")
        XCTAssertEqual(DisplayText.popupChip(kind: " ", camera: " Garage ", date: at, timeZone: tz), "Garage · 10:41")
        XCTAssertEqual(DisplayText.popupChip(kind: nil, camera: "  ", date: at, timeZone: tz), "Kamera · 10:41")
    }

    func testDayAndTime() {
        let now = date("2026-10-18T12:00:00+02:00")
        XCTAssertEqual(DisplayText.dayAndTime(date("2026-10-18T10:12:00+02:00"), now: now, timeZone: tz), "heute, 10:12")
        XCTAssertEqual(DisplayText.dayAndTime(date("2026-10-17T18:22:00+02:00"), now: now, timeZone: tz), "gestern, 18:22")
        XCTAssertEqual(DisplayText.dayAndTime(date("2026-10-12T09:30:00+02:00"), now: now, timeZone: tz), "12.10., 09:30")
    }

    func testShortTime() {
        let now = date("2026-10-18T12:00:00+02:00")
        XCTAssertEqual(DisplayText.shortTime(date("2026-10-18T10:12:00+02:00"), now: now, timeZone: tz), "10:12")
        XCTAssertEqual(DisplayText.shortTime(date("2026-10-17T18:22:00+02:00"), now: now, timeZone: tz), "gestern")
        XCTAssertEqual(DisplayText.shortTime(date("2026-10-12T09:30:00+02:00"), now: now, timeZone: tz), "12.10.")
    }

    func testUntil() {
        let now = date("2026-10-18T10:41:00+02:00")
        XCTAssertEqual(DisplayText.until(date("2026-10-18T10:56:00+02:00"), now: now, timeZone: tz), "bis 10:56")
        XCTAssertEqual(DisplayText.until(date("2026-10-19T09:00:00+02:00"), now: now, timeZone: tz), "bis morgen, 09:00")
        XCTAssertEqual(DisplayText.until(date("2026-10-20T09:00:00+02:00"), now: now, timeZone: tz), "bis 20.10., 09:00")
    }

    func testCameraState() {
        let muted = date("2026-10-18T10:56:00+02:00")
        XCTAssertEqual(DisplayText.cameraState(triggerLabels: ["Klingel", "Person", "Paket"], webhook: false, mutedUntil: nil, timeZone: tz), "Klingel, Person, Paket")
        XCTAssertEqual(DisplayText.cameraState(triggerLabels: [], webhook: false, mutedUntil: nil, timeZone: tz), "aus")
        XCTAssertEqual(DisplayText.cameraState(triggerLabels: [], webhook: true, mutedUntil: nil, timeZone: tz), "Webhook")
        XCTAssertEqual(DisplayText.cameraState(triggerLabels: ["Fahrzeug"], webhook: true, mutedUntil: nil, timeZone: tz), "Fahrzeug, Webhook")
        XCTAssertEqual(DisplayText.cameraState(triggerLabels: ["Person"], webhook: false, mutedUntil: muted, timeZone: tz), "stumm bis 10:56")
    }

    func testActionAddress() {
        XCTAssertEqual(DisplayText.actionAddress("https://homeassistant.local/api/webhook/tuer-auf"), "homeassistant.local/api/webhook/tuer-auf")
        XCTAssertEqual(DisplayText.actionAddress("HTTP://shelly-eingang.local/relay/0?turn=on"), "shelly-eingang.local/relay/0?turn=on")
        XCTAssertEqual(DisplayText.actionAddress("  ftp://x  "), "ftp://x")
    }
}
