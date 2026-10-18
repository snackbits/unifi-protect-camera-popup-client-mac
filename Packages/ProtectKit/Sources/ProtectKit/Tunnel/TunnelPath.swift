import Foundation

/// Which traffic besides the Protect API and RTSP goes through the tunnel while away.
/// Forwards only work for IP literals inside AllowedIPs (the tunnel has no DNS).
public enum TunnelPath {
    /// Where a webhook call (popup action button) goes through the tunnel: only http(s)
    /// to an IP literal inside AllowedIPs (a LAN target). nil = call it directly.
    public static func webhookTarget(_ url: URL, allowedIPs: [String]) -> ForwardTarget? {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = comps.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let rawHost = comps.host, !rawHost.isEmpty else { return nil }
        let host = unbracketed(rawHost)
        guard AllowedIPs.covers(host: host, prefixes: allowedIPs) == true else { return nil }
        return ForwardTarget(host: host, port: comps.port ?? (scheme == "https" ? 443 : 80))
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
