import Foundation

/// Decides when to look up a DynDNS endpoint again while the Mac stays on one network.
///
/// A network change or wake rebinds and re-resolves anyway. What they miss: the home IP
/// behind `Endpoint = name.example.org:…` changes while the Mac sits on the same network,
/// so the peer goes silent. With a persistent keepalive WireGuard handshakes about every
/// two minutes; no handshake for `stallAfter` seconds means the peer stopped answering.
/// Then the name is looked up right away, again after `firstRetry` seconds, doubling up
/// to `maxRetry`. A fresh handshake or `reset(at:)` (network change, wake) starts over.
public struct EndpointReresolve: Sendable {
    public let stallAfter: TimeInterval
    public let firstRetry: TimeInterval
    public let maxRetry: TimeInterval
    /// Stall is measured from the newer of the last handshake and this (start, reset).
    private var since: Date
    private var nextAt: Date?
    private var interval: TimeInterval

    public init(since: Date, stallAfter: TimeInterval = 180,
                firstRetry: TimeInterval = 60, maxRetry: TimeInterval = 600) {
        self.since = since
        self.stallAfter = stallAfter
        self.firstRetry = firstRetry
        self.maxRetry = maxRetry
        self.interval = firstRetry
    }

    /// Network change or wake: those already re-resolved, so the stall clock starts again.
    public mutating func reset(at now: Date) {
        since = now
        nextAt = nil
        interval = firstRetry
    }

    /// True when the endpoint should be looked up now; then the next lookup is scheduled.
    /// `lastHandshake`: newest completed handshake, nil when there was none yet.
    public mutating func shouldReresolve(lastHandshake: Date?, now: Date) -> Bool {
        let reference = max(lastHandshake ?? since, since)
        guard now.timeIntervalSince(reference) >= stallAfter else {
            // Handshakes flow (again): the next stall starts with a lookup at once.
            nextAt = nil
            interval = firstRetry
            return false
        }
        if let nextAt, now < nextAt { return false }
        nextAt = now.addingTimeInterval(interval)
        interval = min(interval * 2, maxRetry)
        return true
    }

    /// Whether a wg-quick endpoint (`host:port`, `[v6]:port`) names a host rather than an
    /// IP: only a name can point somewhere else later.
    public static func isHostName(endpoint: String) -> Bool {
        var host = endpoint.trimmingCharacters(in: .whitespaces)
        if host.hasPrefix("[") { return false }  // bracketed IPv6 literal
        if let colon = host.lastIndex(of: ":") { host = String(host[..<colon]) }
        if host.isEmpty || host.contains(":") { return false }  // empty, bare IPv6
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        let isIPv4 = parts.count == 4 && parts.allSatisfy { part in
            !part.isEmpty && part.count <= 3 && part.allSatisfy(\.isASCIIDigit) && Int(part)! <= 255
        }
        return !isIPv4
    }
}

private extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}

/// `WgReresolve` JSON: `{"updates":[{"host":…,"ip":…,"changed":…}]}`, plus `"error"`.
public struct TunnelReresolveResult: Decodable, Equatable, Sendable {
    public struct Update: Decodable, Equatable, Sendable {
        public var host: String
        public var ip: String
        public var changed: Bool

        public init(host: String, ip: String, changed: Bool) {
            self.host = host
            self.ip = ip
            self.changed = changed
        }
    }

    public var updates: [Update]
    public var error: String?

    public init(updates: [Update], error: String?) {
        self.updates = updates
        self.error = error
    }

    private enum CodingKeys: String, CodingKey { case updates, error }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        updates = try c.decodeIfPresent([Update].self, forKey: .updates) ?? []
        error = try c.decodeIfPresent(String.self, forKey: .error)
    }

    public static func decode(_ json: String) -> TunnelReresolveResult {
        (try? JSONDecoder().decode(TunnelReresolveResult.self, from: Data(json.utf8)))
            ?? TunnelReresolveResult(updates: [], error: "Unerwartete Antwort des Tunnel-Moduls.")
    }
}
