import Foundation

/// Which traffic besides the Protect API and RTSP goes through the tunnel while away.
/// Forwards only work for IP literals inside AllowedIPs (the tunnel has no DNS).
public enum TunnelPath {
    public enum Webhook: Equatable, Sendable {
        /// Called as configured (at home, or a public address / host name away).
        case direct
        /// Away: through a local forward to this LAN target (IP literal inside AllowedIPs).
        case forward(ForwardTarget)
        /// Away: a private address outside AllowedIPs. Calling it directly would reach
        /// whatever device has that address on the foreign network (with the token).
        case refuse
    }

    /// Private, link-local and unique-local ranges: never meant for the foreign network.
    public static let privateRanges = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16",
                                       "169.254.0.0/16", "fc00::/7", "fe80::/10"]

    /// Where a webhook call (popup action button) goes. Away from home the Bearer token must
    /// never reach the foreign network:
    /// - an IP literal inside AllowedIPs goes through a forward (http or https);
    ///   IPv4-mapped, IPv4-compatible, NAT64 and 6to4 addresses count as their embedded IPv4;
    /// - otherwise only https goes out directly (TLS checks the host name, so the foreign
    ///   network's DNS or devices cannot pose as the target); plain http is refused;
    /// - always refused: private literals outside AllowedIPs, mDNS names (`.local`, answered
    ///   by any device on the current link), numeric spellings that are no canonical dotted
    ///   quad, and anything with a colon that is no plain IPv6 literal (zone IDs).
    public static func webhook(_ url: URL, route: ProtectRoute, allowedIPs: [String]) -> Webhook {
        guard route == .tunnel else { return .direct }
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = comps.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let rawHost = comps.host, !rawHost.isEmpty else { return .refuse }
        let https = scheme == "https"
        switch classify(host: rawHost) {
        case .invalid, .ambiguousNumeric:
            return .refuse
        case .name(let name):
            return https && !isMDNS(name) ? .direct : .refuse
        case .address(let ip):
            if AllowedIPs.covers(host: ip, prefixes: allowedIPs) == true {
                // A port outside 1…65535 is refused, never clamped.
                guard let target = ForwardTarget(host: ip, port: comps.port ?? (https ? 443 : 80)) else { return .refuse }
                return .forward(target)
            }
            if AllowedIPs.covers(host: ip, prefixes: privateRanges) == true { return .refuse }
            return https ? .direct : .refuse
        }
    }

    enum HostClass: Equatable {
        /// Canonical IP literal; IPv6 forms that embed an IPv4 (mapped ::ffff:a.b.c.d,
        /// compatible ::a.b.c.d, NAT64 64:ff9b::/96, 6to4 2002::/16) are given as that IPv4.
        case address(String)
        /// Looks like a number (hex, octal, short or integer IPv4 forms) but is no canonical
        /// dotted quad: resolvers disagree on what it means.
        case ambiguousNumeric
        /// Contains a colon but is no plain IPv6 literal (zone ID, garbage).
        case invalid
        /// Lowercased host name.
        case name(String)
    }

    static func classify(host raw: String) -> HostClass {
        let host = unbracketed(raw)
        // Darwin's inet_pton accepts "fe80::1%en0": a zone ID names an interface of this Mac
        // (the foreign link), so it is refused before parsing.
        guard !host.contains("%") else { return .invalid }
        var v6 = in6_addr()
        if inet_pton(AF_INET6, host, &v6) == 1 {
            let b = withUnsafeBytes(of: &v6) { Array($0) }
            if let embedded = embeddedIPv4(b) { return .address(embedded.map(String.init).joined(separator: ".")) }
            return .address(host)
        }
        guard !host.contains(":") else { return .invalid }
        var labels = host.split(separator: ".", omittingEmptySubsequences: false).map { $0.lowercased() }
        let trailingDot = labels.count > 1 && labels.last == ""
        if trailingDot { labels.removeLast() }
        let numeric = labels.allSatisfy { label in
            guard !label.isEmpty else { return false }
            if label.hasPrefix("0x") { return label.dropFirst(2).allSatisfy(\.isHexDigit) }
            return label.allSatisfy { $0.isASCII && $0.isNumber }
        }
        guard numeric else { return .name(host.lowercased()) }
        let canonical = !trailingDot && labels.count == 4 && labels.allSatisfy { label in
            guard let value = Int(label), (0...255).contains(value) else { return false }
            return label == String(value)  // no leading zeros (octal in some resolvers)
        }
        return canonical ? .address(host) : .ambiguousNumeric
    }

    /// The IPv4 inside an IPv6 address that carries one, nil otherwise.
    private static func embeddedIPv4(_ b: [UInt8]) -> ArraySlice<UInt8>? {
        let zeros = { (range: Range<Int>) in b[range].allSatisfy { $0 == 0 } }
        if zeros(0..<10), b[10] == 0xFF, b[11] == 0xFF { return b[12..<16] }        // ::ffff:a.b.c.d
        if b[0..<4] == [0x00, 0x64, 0xFF, 0x9B], zeros(4..<12) { return b[12..<16] }  // 64:ff9b::/96
        if b[0] == 0x20, b[1] == 0x02 { return b[2..<6] }                            // 2002::/16
        // ::a.b.c.d, but not :: and ::1.
        if zeros(0..<12), !(zeros(12..<15) && b[15] <= 1) { return b[12..<16] }
        return nil
    }

    private static func isMDNS(_ name: String) -> Bool {
        let trimmed = name.hasSuffix(".") ? String(name.dropLast()) : name
        return trimmed == "local" || trimmed.hasSuffix(".local")
    }

    /// Same URL on 127.0.0.1:<localPort>; scheme, path and query stay (TLS stays end to end).
    public static func rewrite(_ url: URL, localPort: Int) -> URL? {
        ForwardURL.rewrite(url.absoluteString, localPort: localPort).flatMap(URL.init(string:))
    }

    public enum Talkback: Equatable, Sendable {
        /// At home: UDP straight to the camera.
        case direct
        /// Away: UDP to a local forward that leads to `ip:port` through the tunnel.
        case forward(ip: String, port: Int)
        /// Away, but the camera address is not inside AllowedIPs (or not an IP literal),
        /// or the port lies outside 1…65535.
        case notRouted
    }

    /// Where talkback audio for the camera endpoint from the talkback session goes.
    public static func talkback(host: String, port: Int, route: ProtectRoute, allowedIPs: [String]) -> Talkback {
        guard route == .tunnel else { return .direct }
        let ip = unbracketed(host.trimmingCharacters(in: .whitespacesAndNewlines))
        guard AllowedIPs.covers(host: ip, prefixes: allowedIPs) == true,
              ForwardTarget.validPorts.contains(port) else { return .notRouted }
        return .forward(ip: ip, port: port)
    }

    private static func unbracketed(_ host: String) -> String {
        host.hasPrefix("[") && host.hasSuffix("]") ? String(host.dropFirst().dropLast()) : host
    }
}
