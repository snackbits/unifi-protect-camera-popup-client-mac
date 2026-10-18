import Foundation

/// Non-secret part of a WireGuard config as reported by the Go parser (`WgParse`).
/// Safe to keep outside the keychain: it never contains a key.
public struct TunnelConfigSummary: Codable, Equatable, Sendable {
    public var endpoint: String
    public var addresses: [String]
    public var allowedIPs: [String]
    public var dns: [String]
    public var warnings: [String]

    public init(endpoint: String, addresses: [String] = [], allowedIPs: [String] = [],
                dns: [String] = [], warnings: [String] = []) {
        self.endpoint = endpoint
        self.addresses = addresses
        self.allowedIPs = allowedIPs
        self.dns = dns
        self.warnings = warnings
    }
}

/// Result of `WgParse`: `{"ok":true,"summary":{…}}` or `{"ok":false,"error":"…"}`.
public enum TunnelParseResult: Equatable, Sendable {
    case valid(TunnelConfigSummary)
    case invalid(String)

    public static func decode(_ json: String) -> TunnelParseResult {
        struct Wire: Decodable {
            let ok: Bool
            let summary: TunnelConfigSummary?
            let error: String?
        }
        guard let wire = try? JSONDecoder().decode(Wire.self, from: Data(json.utf8)) else {
            return .invalid("Unerwartete Antwort des Tunnel-Moduls.")
        }
        if wire.ok, let summary = wire.summary { return .valid(summary) }
        return .invalid(wire.error ?? "Die Datei ist keine gültige WireGuard-Konfiguration.")
    }
}

/// `WgStatus` JSON. `{"up":false}` when the tunnel is stopped.
public struct TunnelStatus: Decodable, Equatable, Sendable {
    public struct Peer: Decodable, Equatable, Sendable {
        public var endpoint: String
        public var lastHandshakeUnix: Int64
        public var handshakeAgeSeconds: Int64
        public var rxBytes: Int64
        public var txBytes: Int64

        public init(endpoint: String, lastHandshakeUnix: Int64, handshakeAgeSeconds: Int64,
                    rxBytes: Int64, txBytes: Int64) {
            self.endpoint = endpoint
            self.lastHandshakeUnix = lastHandshakeUnix
            self.handshakeAgeSeconds = handshakeAgeSeconds
            self.rxBytes = rxBytes
            self.txBytes = txBytes
        }
    }

    public var up: Bool
    public var peers: [Peer]
    public var error: String?

    public static let stopped = TunnelStatus(up: false, peers: [], error: nil)

    public init(up: Bool, peers: [Peer], error: String?) {
        self.up = up
        self.peers = peers
        self.error = error
    }

    private enum CodingKeys: String, CodingKey { case up, peers, error }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        up = try c.decode(Bool.self, forKey: .up)
        peers = try c.decodeIfPresent([Peer].self, forKey: .peers) ?? []
        error = try c.decodeIfPresent(String.self, forKey: .error)
    }

    public static func decode(_ json: String) -> TunnelStatus {
        (try? JSONDecoder().decode(TunnelStatus.self, from: Data(json.utf8))) ?? .stopped
    }

    /// Received bytes over all peers (the app uses exactly one).
    public var rxBytes: Int64 { peers.reduce(0) { $0 + $1.rxBytes } }

    /// Most recent completed handshake, nil when there was none yet.
    public var lastHandshake: Date? {
        guard let newest = peers.map(\.lastHandshakeUnix).max(), newest > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(newest))
    }
}
