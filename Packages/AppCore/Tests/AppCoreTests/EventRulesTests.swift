import XCTest
@testable import AppCore

final class EventRulesTests: XCTestCase {
    private let door = "DOOR-ENTRY"
    private let gong = UUID(uuidString: "6F0C6A52-4C4B-4E58-9B1E-2F3C1C0A0001")!

    private func rule(_ kind: String, url: String? = nil, sound: UUID? = nil) -> EventRule {
        EventRule(kind: kind, webhook: url.map { EventRuleWebhook(method: "POST", url: $0) }, soundId: sound)
    }

    func testTokenNeverEncoded() throws {
        let secret = EventRule(kind: "ring", webhook: EventRuleWebhook(url: "https://ha.local/x"), bearerToken: "geheim-123")
        let json = String(decoding: try JSONEncoder().encode(EventRuleList([secret])), as: UTF8.self)
        XCTAssertFalse(json.contains("geheim-123"))
        XCTAssertFalse(json.contains("bearerToken"))
        let back = try JSONDecoder().decode(EventRuleList.self, from: Data(json.utf8))
        XCTAssertEqual(back.rules.first?.id, secret.id)
        XCTAssertEqual(back.rules.first?.bearerToken, "")
    }

    func testLenientListKeepsGoodEntries() throws {
        let json = #"[{"kind":"ring","delaySeconds":"x"},42,{"nokind":true},{"kind":"motion","delaySeconds":9999,"webhook":{"method":"PUT","url":"http://a.b"}}]"#
        let list = try JSONDecoder().decode(EventRuleList.self, from: Data(json.utf8))
        XCTAssertEqual(list.rules.map(\.kind), ["ring", "motion"])
        XCTAssertEqual(list.rules[0].delaySeconds, 0)
        XCTAssertEqual(list.rules[1].delaySeconds, 600)
        XCTAssertEqual(list.rules[1].webhook?.method, "POST")
    }

    func testDelayFromText() {
        XCTAssertEqual(EventRule.delay(fromText: ""), 0)
        XCTAssertEqual(EventRule.delay(fromText: "abc"), 0)
        XCTAssertEqual(EventRule.delay(fromText: "-5"), 5)
        XCTAssertEqual(EventRule.delay(fromText: "45 s"), 45)
        XCTAssertEqual(EventRule.delay(fromText: "9999"), 600)
        XCTAssertEqual(EventRule.delay(fromText: "99999999999999999999"), 600)
        XCTAssertEqual(EventRule(kind: "ring", delaySeconds: -3).delaySeconds, 0)
    }

    func testIsConfigured() {
        XCTAssertFalse(rule("ring").isConfigured)
        XCTAssertTrue(rule("ring", url: "https://ha.local/hook").isConfigured)
        XCTAssertFalse(rule("ring", url: "ha.local/hook").isConfigured, "invalid address never saves")
        XCTAssertFalse(rule("ring", url: "ftp://x", sound: gong).isConfigured)
        XCTAssertTrue(rule("ring", url: "  ", sound: gong).isConfigured)
        XCTAssertTrue(rule("ring", sound: gong).isConfigured)
    }

    func testMatcherPicksKindAndSkipsRulesThatCannotRun() {
        let rules = [
            rule("ring", url: "https://ha.local/a"),
            rule("person", url: "https://ha.local/b"),
            rule("ring", sound: gong),
            rule("ring", sound: UUID()),            // announcement deleted
            rule("ring", url: "https://ha.local/c", sound: gong),
        ]
        let withSpeaker = EventRuleMatcher.matching(rules, kinds: ["ring"], canPlaySound: true) { $0 == self.gong }
        XCTAssertEqual(withSpeaker.map(\.id), [rules[0].id, rules[2].id, rules[4].id])
        let noSpeaker = EventRuleMatcher.matching(rules, kinds: ["ring"], canPlaySound: false) { $0 == self.gong }
        XCTAssertEqual(noSpeaker.map(\.id), [rules[0].id, rules[4].id], "webhook part still runs")
        let both = EventRuleMatcher.matching(rules, kinds: ["ring", "person"], canPlaySound: true) { _ in true }
        XCTAssertEqual(both.count, 5, "each rule once per event, even with several kinds")
    }

    func testDebouncePerCameraAndRule() {
        var debouncer = EventRuleDebouncer()
        let start = Date(timeIntervalSince1970: 1_000_000)
        let a = UUID(), b = UUID()
        XCTAssertTrue(debouncer.shouldRun(entry: door, rule: a, at: start))
        XCTAssertFalse(debouncer.shouldRun(entry: door, rule: a, at: start.addingTimeInterval(10)))
        XCTAssertFalse(debouncer.shouldRun(entry: door, rule: a, at: start.addingTimeInterval(29.9)))
        XCTAssertTrue(debouncer.shouldRun(entry: door, rule: b, at: start.addingTimeInterval(10)), "other rule")
        XCTAssertTrue(debouncer.shouldRun(entry: "GARAGE", rule: a, at: start.addingTimeInterval(10)), "other camera")
        XCTAssertTrue(debouncer.shouldRun(entry: door, rule: a, at: start.addingTimeInterval(30)))
        // Clock set back: still "just now".
        XCTAssertFalse(debouncer.shouldRun(entry: door, rule: a, at: start.addingTimeInterval(20)))
    }

    func testBurstOfEventsRunsOncePerWindow() {
        var debouncer = EventRuleDebouncer()
        let start = Date(timeIntervalSince1970: 2_000_000)
        let id = UUID()
        let runs = (0..<10).filter { debouncer.shouldRun(entry: door, rule: id, at: start.addingTimeInterval(Double($0) * 5)) }
        XCTAssertEqual(runs, [0, 6], "every 5 s for 50 s → at 0 s and 30 s")
    }

    func testTexts() {
        XCTAssertEqual(EventRuleText.actionSummary(webhookAddress: "ha.local/hook", soundName: "Bin gleich da", delaySeconds: 10),
                       "ha.local/hook + „Bin gleich da“ · nach 10 s")
        XCTAssertEqual(EventRuleText.actionSummary(webhookAddress: nil, soundName: nil, delaySeconds: 0), "Keine Aktion")
        XCTAssertEqual(EventRuleText.logTitle(kindLabel: "Klingel", webhook: true, soundName: "Gong", failed: false),
                       "Klingel → Webhook + „Gong“")
        XCTAssertEqual(EventRuleText.logTitle(kindLabel: "Paket", webhook: true, soundName: nil, failed: true),
                       "Paket → Webhook (fehlgeschlagen)")
    }

    func testWebhookURLValidation() {
        XCTAssertNotNil(EventRuleWebhook(url: " https://ha.local/api ").requestURL)
        XCTAssertNil(EventRuleWebhook(url: "https://").requestURL)
        XCTAssertNil(EventRuleWebhook(url: "mailto:x@y").requestURL)
    }
}
