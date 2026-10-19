import Foundation

public enum AllowedIPs {
    /// Whether `host` lies inside one of the CIDR `prefixes` (e.g. "192.168.1.0/24", "::/0").
    /// nil when `host` is a name: whether it is routed only shows once it resolves.
    /// An address with a zone ID ("fe80::1%en0", accepted by Darwin's inet_pton) is never
    /// covered: it names an interface of this Mac, not a host behind the tunnel.
    public static func covers(host: String, prefixes: [String]) -> Bool? {
        if host.contains("%") { return false }
        guard let address = bytes(of: host) else { return nil }
        for prefix in prefixes {
            let parts = prefix.split(separator: "/", maxSplits: 1).map(String.init)
            guard let first = parts.first, !first.contains("%"), let net = bytes(of: first), net.count == address.count else { continue }
            let bits = parts.count == 2 ? Int(parts[1]) ?? -1 : net.count * 8
            guard bits >= 0, bits <= net.count * 8 else { continue }
            if matches(address, net, bits: bits) { return true }
        }
        return false
    }

    private static func bytes(of literal: String) -> [UInt8]? {
        var v4 = in_addr()
        if inet_pton(AF_INET, literal, &v4) == 1 {
            return withUnsafeBytes(of: &v4) { Array($0) }
        }
        var v6 = in6_addr()
        if inet_pton(AF_INET6, literal, &v6) == 1 {
            return withUnsafeBytes(of: &v6) { Array($0) }
        }
        return nil
    }

    private static func matches(_ a: [UInt8], _ b: [UInt8], bits: Int) -> Bool {
        var remaining = bits
        for i in 0..<a.count where remaining > 0 {
            let take = min(8, remaining)
            let mask: UInt8 = take == 8 ? 0xFF : ~(UInt8(0xFF) >> UInt8(take))
            if a[i] & mask != b[i] & mask { return false }
            remaining -= take
        }
        return true
    }
}
