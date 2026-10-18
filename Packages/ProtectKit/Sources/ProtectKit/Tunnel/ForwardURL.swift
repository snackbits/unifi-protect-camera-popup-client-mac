import Foundation

/// A TCP or UDP destination behind the tunnel.
public struct ForwardTarget: Hashable, Sendable {
    public let host: String
    public let port: Int

    /// nil for a port outside 1…65535 (refused, never clamped: the C API takes an `Int32`)
    /// and for a host with a zone ID ("fe80::1%en0" names an interface of this Mac).
    public init?(host: String, port: Int) {
        guard Self.validPorts.contains(port), !host.isEmpty, !host.contains("%") else { return nil }
        self.host = host
        self.port = port
    }

    public static let validPorts = 1...65535
}

/// Maps console and camera addresses onto local forwards (127.0.0.1:<port>).
/// The certificate pin is unaffected: `ProtectClient` compares the leaf
/// certificate's fingerprint and never the host name.
public enum ForwardURL {
    /// Where the Protect API lives for a configured console address ("h", "h:8443", "[fd00::1]").
    public static func apiTarget(consoleHost: String) -> ForwardTarget? {
        guard let url = ProtectClient.baseURL(for: consoleHost),
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = comps.host.map(unbracketed), !host.isEmpty else { return nil }
        return ForwardTarget(host: host, port: comps.port ?? 443)  // nil for a port outside 1…65535
    }

    /// The host string handed to `ProtectClient` for a forward.
    public static func localHost(port: Int) -> String {
        "127.0.0.1:\(port)"
    }

    /// rtsp://h:7447/x → (h, 7447). Port defaults to 554 (RTSP) when missing.
    public static func streamTarget(_ url: String) -> ForwardTarget? {
        guard let comps = URLComponents(string: url),
              comps.scheme?.lowercased() == "rtsp",
              let host = comps.host.map(unbracketed), !host.isEmpty else { return nil }
        return ForwardTarget(host: host, port: comps.port ?? 554)  // nil for a port outside 1…65535
    }

    /// Same URL with host and port replaced by 127.0.0.1:<localPort>; path and query stay.
    public static func rewrite(_ url: String, localPort: Int) -> String? {
        guard var comps = URLComponents(string: url), comps.host != nil else { return nil }
        comps.host = "127.0.0.1"
        comps.port = localPort
        return comps.string
    }

    private static func unbracketed(_ host: String) -> String {
        host.hasPrefix("[") && host.hasSuffix("]") ? String(host.dropFirst().dropLast()) : host
    }
}
