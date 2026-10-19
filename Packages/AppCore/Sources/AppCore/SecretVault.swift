import Foundation

/// Every secret of the app in one value (service → account → secret), so the login keychain holds a
/// single item. A self-signed app without an Apple team ID is asked for the keychain password per
/// item after each update – one item means one prompt, however many secrets there are.
public struct SecretVault: Equatable, Sendable {
    public private(set) var entries: [String: [String: String]]

    public init(entries: [String: [String: String]] = [:]) {
        self.entries = entries.filter { !$0.value.isEmpty }
    }

    public func value(service: String, account: String) -> String? {
        entries[service]?[account]
    }

    public mutating func set(_ value: String, service: String, account: String) {
        entries[service, default: [:]][account] = value
    }

    public mutating func remove(service: String, account: String) {
        entries[service]?[account] = nil
        if entries[service]?.isEmpty == true { entries[service] = nil }
    }

    public func accounts(service: String) -> [String] {
        (entries[service] ?? [:]).keys.sorted()
    }

    public var isEmpty: Bool { entries.isEmpty }

    /// Stable JSON (sorted keys) – the keychain item's data.
    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(entries)) ?? Data("{}".utf8)
    }

    /// Nil for data that is not a vault (never silently replaced by an empty one).
    public static func decode(_ data: Data) -> SecretVault? {
        guard let entries = try? JSONDecoder().decode([String: [String: String]].self, from: data) else { return nil }
        return SecretVault(entries: entries)
    }
}
