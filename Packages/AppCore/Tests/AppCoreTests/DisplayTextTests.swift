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
        let now = date("2026-10-18T10:41:00+02:00")
        XCTAssertEqual(DisplayText.cameraState(triggerLabels: ["Person"], webhook: false, mutedUntil: muted, now: now, timeZone: tz), "stumm bis 10:56")
        XCTAssertEqual(DisplayText.cameraState(triggerLabels: ["Person"], webhook: false, mutedUntil: date("2026-10-19T09:00:00+02:00"), now: now, timeZone: tz), "stumm bis morgen, 09:00")
        XCTAssertEqual(DisplayText.cameraState(triggerLabels: ["Person"], webhook: false, mutedUntil: date("2026-10-20T09:00:00+02:00"), now: now, timeZone: tz), "stumm bis 20.10., 09:00")
    }

    func testActionAddress() {
        XCTAssertEqual(DisplayText.actionAddress("https://homeassistant.local/api/webhook/tuer-auf"), "homeassistant.local/api/webhook/tuer-auf")
        XCTAssertEqual(DisplayText.actionAddress("HTTP://shelly-eingang.local/relay/0?turn=on"), "shelly-eingang.local/relay/0?turn=on")
        XCTAssertEqual(DisplayText.actionAddress("  ftp://x  "), "ftp://x")
    }
}

final class DisplayTextPhase5Tests: XCTestCase {
    func testVersionAndUpdateTexts() {
        XCTAssertEqual(DisplayText.version(short: "1.2.0"), "Version 1.2.0")
        XCTAssertEqual(DisplayText.updateButton(targetShort: "1.3.0", currentShort: "1.2.0"), "Update auf 1.3.0 installieren")
        XCTAssertEqual(DisplayText.updateButton(targetShort: "1.2.0", currentShort: "1.2.0"), "Update installieren")
        XCTAssertEqual(DisplayText.updateButton(targetShort: nil, currentShort: "1.2.0"), "Update installieren")
        XCTAssertEqual(DisplayText.updateButton(targetShort: " ", currentShort: "1.2.0"), "Update installieren")
    }

    func testActionTarget() {
        XCTAssertEqual(DisplayText.actionTarget(url: "https://ha.local/x", soundName: nil), "ha.local/x")
        XCTAssertEqual(DisplayText.actionTarget(url: "https://ha.local/x", soundName: "Gong"), "ha.local/x + Ton")
        XCTAssertEqual(DisplayText.actionTarget(url: " ", soundName: "Gong"), "Ton „Gong“")
        XCTAssertEqual(DisplayText.actionTarget(url: "", soundName: nil), "")
    }
}

final class PopupChipLiveTests: XCTestCase {
    func testLiveClockShowsSeconds() {
        let tz = TimeZone(identifier: "Europe/Berlin")!
        var parts = DateComponents()
        parts.year = 2026; parts.month = 10; parts.day = 19; parts.hour = 10; parts.minute = 41; parts.second = 7
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        let at = calendar.date(from: parts)!
        XCTAssertEqual(DisplayText.popupChip(kind: "Bewegung", camera: "Garten", date: at, seconds: true, timeZone: tz),
                       "Bewegung · Garten · 10:41:07")
        XCTAssertEqual(DisplayText.popupChip(kind: nil, camera: "", date: at, seconds: true, timeZone: tz), "Kamera · 10:41:07")
        XCTAssertEqual(DisplayText.timeWithSeconds(at, timeZone: tz), "10:41:07")
    }
}
