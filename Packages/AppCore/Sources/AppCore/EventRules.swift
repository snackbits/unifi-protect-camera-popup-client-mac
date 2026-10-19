import Foundation

/// Webhook part of an event rule: same request as a popup button.
public struct EventRuleWebhook: Codable, Equatable, Sendable {
    public var method: String
    public var url: String

    public init(method: String = "POST", url: String = "") {
        self.method = method == "GET" ? "GET" : "POST"
        self.url = url
    }

    /// A valid http(s) URL with a host, else nil.
    public var requestURL: URL? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: trimmed),
              let scheme = parsed.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              parsed.host?.isEmpty == false else { return nil }
        return parsed
    }

    private enum CodingKeys: String, CodingKey { case method, url }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            method: (try? c.decodeIfPresent(String.self, forKey: .method)) ?? "POST",
            url: (try? c.decodeIfPresent(String.self, forKey: .url)) ?? ""
        )
    }
}

/// Kameras › Ereignisse: when the camera reports `kind`, call a webhook and/or play an announcement
/// at the camera, after `delaySeconds`. Runs regardless of popups and mutes.
public struct EventRule: Codable, Equatable, Identifiable, Sendable {
    public static let maxDelay = 600
    /// The same rule fires at most once per camera within this window.
    public static let debounce: TimeInterval = 30
    public static let maxPerCamera = 10

    public var id: UUID
    /// `TriggerKind` raw value ("ring", "motion", "person", …).
    public var kind: String
    public var webhook: EventRuleWebhook?
    /// Bearer token: lives in the keychain only and is never encoded (settings, extension, export).
    public var bearerToken: String
    /// Announcement id (Einstellungen › Ton); nil = no sound.
    public var soundId: UUID?
    /// 0…600 seconds.
    public var delaySeconds: Int

    public init(
        id: UUID = UUID(),
        kind: String = "ring",
        webhook: EventRuleWebhook? = nil,
        bearerToken: String = "",
        soundId: UUID? = nil,
        delaySeconds: Int = 0
    ) {
        self.id = id
        self.kind = kind
        self.webhook = webhook
        self.bearerToken = bearerToken
        self.soundId = soundId
        self.delaySeconds = Self.clampedDelay(delaySeconds)
    }

    /// A webhook that can be called (valid address).
    public var hasWebhook: Bool { webhook?.requestURL != nil }

    /// Saveable: a valid webhook, or a sound with an empty address field.
    public var isConfigured: Bool {
        let addressEmpty = webhook?.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        return addressEmpty ? soundId != nil : hasWebhook
    }

    public static func clampedDelay(_ seconds: Int) -> Int {
        min(maxDelay, max(0, seconds))
    }

    /// "Verzögerung" field → seconds: digits only, empty = 0, at most 600.
    public static func delay(fromText text: String) -> Int {
        let digits = text.filter { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty else { return 0 }
        return clampedDelay(Int(digits.prefix(4)) ?? maxDelay)
    }

    private enum CodingKeys: String, CodingKey { case id, kind, webhook, soundId, delaySeconds }

    /// Lenient: only `kind` is required; a broken field falls back to its default.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        self.init(
            id: (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID(),
            kind: kind,
            webhook: (try? c.decodeIfPresent(EventRuleWebhook.self, forKey: .webhook)) ?? nil,
            soundId: (try? c.decodeIfPresent(UUID.self, forKey: .soundId)) ?? nil,
            delaySeconds: (try? c.decodeIfPresent(Int.self, forKey: .delaySeconds)) ?? 0
        )
    }

    /// The token is deliberately left out.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(webhook, forKey: .webhook)
        try c.encodeIfPresent(soundId, forKey: .soundId)
        try c.encode(delaySeconds, forKey: .delaySeconds)
    }
}

/// A list of rules that survives broken entries (each element decoded on its own).
public struct EventRuleList: Codable, Equatable, Sendable {
    public var rules: [EventRule]

    public init(_ rules: [EventRule] = []) {
        self.rules = rules
    }

    private struct Skip: Decodable {
        init(from decoder: Decoder) throws {}
    }

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var rules: [EventRule] = []
        while !container.isAtEnd {
            if let rule = try? container.decode(EventRule.self) {
                rules.append(rule)
            } else {
                _ = try? container.decode(Skip.self)
            }
        }
        self.rules = rules
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(contentsOf: rules)
    }
}

public enum EventRuleMatcher {
    /// Rules an event with `kinds` triggers, in list order, each once. Rules that could do nothing
    /// here (sound only, but no speaker or the announcement is gone) are left out.
    public static func matching(
        _ rules: [EventRule],
        kinds: Set<String>,
        canPlaySound: Bool,
        soundExists: (UUID) -> Bool
    ) -> [EventRule] {
        rules.filter { rule in
            guard kinds.contains(rule.kind) else { return false }
            let plays = canPlaySound && rule.soundId.map(soundExists) == true
            return rule.hasWebhook || plays
        }
    }
}

/// Per camera entry and rule: at most one run within `EventRule.debounce`.
public struct EventRuleDebouncer: Sendable {
    private var lastRun: [String: Date] = [:]

    public init() {}

    public mutating func shouldRun(entry: String, rule: UUID, at date: Date, window: TimeInterval = EventRule.debounce) -> Bool {
        let key = "\(entry)|\(rule.uuidString)"
        // abs: a clock set back counts as "just now", never as "long ago".
        if let last = lastRun[key], abs(date.timeIntervalSince(last)) < window { return false }
        lastRun = lastRun.filter { abs(date.timeIntervalSince($0.value)) < window }
        lastRun[key] = date
        return true
    }
}

public enum EventRuleText {
    /// Row in Kameras › Ereignisse: "Webhook + „Bin gleich da“ · nach 10 s".
    public static func actionSummary(webhookAddress: String?, soundName: String?, delaySeconds: Int) -> String {
        var parts: [String] = []
        if let webhookAddress, !webhookAddress.isEmpty { parts.append(webhookAddress) }
        if let soundName { parts.append("„\(soundName)“") }
        var text = parts.isEmpty ? "Keine Aktion" : parts.joined(separator: " + ")
        if delaySeconds > 0 { text += " · nach \(delaySeconds) s" }
        return text
    }

    /// Event log / menu panel: "Klingel → Webhook + „Bin gleich da“", "… (fehlgeschlagen)".
    public static func logTitle(kindLabel: String, webhook: Bool, soundName: String?, failed: Bool) -> String {
        var actions: [String] = []
        if webhook { actions.append("Webhook") }
        if let soundName { actions.append("„\(soundName)“") }
        let text = "\(kindLabel) → \(actions.isEmpty ? "nichts" : actions.joined(separator: " + "))"
        return failed ? "\(text) (fehlgeschlagen)" : text
    }
}
