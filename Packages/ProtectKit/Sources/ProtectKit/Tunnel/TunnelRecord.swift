import Foundation

/// When and over which kind of network the tunnel last had a handshake.
public struct TunnelLastConnection: Codable, Equatable, Sendable {
    public var date: Date
    public var via: NetworkKind

    public init(date: Date, via: NetworkKind) {
        self.date = date
        self.via = via
    }
}

/// The non-secret tunnel settings as stored in UserDefaults. There is no field for
/// the config text: the private key exists only in the keychain.
public struct TunnelRecord: Codable, Equatable, Sendable {
    public var mode: TunnelMode
    public var fileName: String?
    public var summary: TunnelConfigSummary?
    public var lastConnection: TunnelLastConnection?

    public init(mode: TunnelMode = .automatic, fileName: String? = nil,
                summary: TunnelConfigSummary? = nil, lastConnection: TunnelLastConnection? = nil) {
        self.mode = mode
        self.fileName = fileName
        self.summary = summary
        self.lastConnection = lastConnection
    }

    private enum CodingKeys: String, CodingKey { case mode, fileName, summary, lastConnection }

    /// Tolerant: an unknown mode (newer build) becomes `.automatic`, broken parts are dropped.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = (try? c.decode(TunnelMode.self, forKey: .mode)) ?? .automatic
        fileName = try? c.decodeIfPresent(String.self, forKey: .fileName)
        summary = try? c.decodeIfPresent(TunnelConfigSummary.self, forKey: .summary)
        lastConnection = try? c.decodeIfPresent(TunnelLastConnection.self, forKey: .lastConnection)
    }

    public static func decode(_ data: Data?) -> TunnelRecord {
        guard let data, let record = try? JSONDecoder().decode(TunnelRecord.self, from: data) else { return TunnelRecord() }
        return record
    }

    public func encoded() -> Data {
        (try? JSONEncoder().encode(self)) ?? Data()
    }

    public var hasConfiguration: Bool { summary != nil }

    /// Metadata without the keychain item (keychain reset, restored backup) is no tunnel;
    /// the mode stays.
    public func reconciled(hasKeychainItem: Bool) -> TunnelRecord {
        guard !hasKeychainItem, hasConfiguration || fileName != nil else { return self }
        return TunnelRecord(mode: mode)
    }
}

public enum TunnelImportCheck {
    /// Non-blocking hint after an import: the console's address lies outside AllowedIPs.
    /// nil when it is inside, or when the console is a name (cannot be checked).
    public static func warning(consoleHost: String, summary: TunnelConfigSummary) -> String? {
        guard let host = ForwardURL.apiTarget(consoleHost: consoleHost)?.host,
              AllowedIPs.covers(host: host, prefixes: summary.allowedIPs) == false else { return nil }
        return TunnelText.consoleNotRouted(host)
    }
}
