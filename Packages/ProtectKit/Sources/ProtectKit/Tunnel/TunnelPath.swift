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

    /// Where a webhook call (popup action button) goes.
    public static func webhook(_ url: URL, route: ProtectRoute, allowedIPs: [String]) -> Webhook {
        guard route == .tunnel,
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = comps.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let rawHost = comps.host, !rawHost.isEmpty else { return .direct }
        let host = unbracketed(rawHost)
        if AllowedIPs.covers(host: host, prefixes: allowedIPs) == true {
            return .forward(ForwardTarget(host: host, port: comps.port ?? (scheme == "https" ? 443 : 80)))
        }
        return AllowedIPs.covers(host: host, prefixes: privateRanges) == true ? .refuse : .direct
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
        /// Away, but the camera address is not inside AllowedIPs (or not an IP literal).
        case notRouted
    }

    /// Where talkback audio for the camera endpoint from the talkback session goes.
    public static func talkback(host: String, port: Int, route: ProtectRoute, allowedIPs: [String]) -> Talkback {
        guard route == .tunnel else { return .direct }
        let ip = unbracketed(host.trimmingCharacters(in: .whitespacesAndNewlines))
        guard AllowedIPs.covers(host: ip, prefixes: allowedIPs) == true else { return .notRouted }
        return .forward(ip: ip, port: port)
    }

    private static func unbracketed(_ host: String) -> String {
        host.hasPrefix("[") && host.hasSuffix("]") ? String(host.dropFirst().dropLast()) : host
    }
}
