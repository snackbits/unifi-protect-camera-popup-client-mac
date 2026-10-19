import XCTest
@testable import AppCore

final class ActionAvailabilityTests: XCTestCase {
    func testConfigured() {
        XCTAssertFalse(ActionAvailability.isConfigured(title: " ", address: "https://a.b", hasValidURL: true, hasSound: false))
        XCTAssertTrue(ActionAvailability.isConfigured(title: "Tür", address: "https://a.b", hasValidURL: true, hasSound: false))
        XCTAssertFalse(ActionAvailability.isConfigured(title: "Tür", address: "", hasValidURL: false, hasSound: false))
        XCTAssertTrue(ActionAvailability.isConfigured(title: "Gong", address: "", hasValidURL: false, hasSound: true),
                      "address only required without sound")
        XCTAssertFalse(ActionAvailability.isConfigured(title: "Gong", address: "kaputt", hasValidURL: false, hasSound: true),
                       "a typed address must be valid")
    }

    func testShownOnlyWhereItCanDoSomething() {
        XCTAssertTrue(ActionAvailability.isShown(hasWebhook: true, hasSound: true, canPlaySound: false))
        XCTAssertFalse(ActionAvailability.isShown(hasWebhook: false, hasSound: true, canPlaySound: false))
        XCTAssertTrue(ActionAvailability.isShown(hasWebhook: false, hasSound: true, canPlaySound: true))
        XCTAssertFalse(ActionAvailability.playsSound(hasSound: true, canPlaySound: false))
    }
}
