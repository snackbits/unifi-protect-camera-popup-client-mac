import Foundation
import Network

/// Answer of `POST /v1/cameras/{id}/talkback-session`: where the camera expects audio.
/// Not verified against real hardware yet, so parsing is tolerant (wrapped in "data",
/// numbers as strings, alternative key spellings, URL with or without scheme/port).
public struct TalkbackSession: Equatable, Sendable {
    public static let defaultPort: UInt16 = 7004

    public let url: String
    public let codec: String
    /// 0 = not given.
    public let samplingRate: Int
    public let bitsPerSample: Int
    public let host: String
    public let port: UInt16
    /// Response body (no secrets) for the diagnosis log, at most 500 characters.
    public let raw: String

    public init(url: String, codec: String, samplingRate: Int, bitsPerSample: Int = 16, raw: String = "") throws {
        guard let endpoint = Self.endpoint(from: url) else { throw ProtectError.decoding }
        self.url = url
        self.codec = codec
        self.samplingRate = samplingRate
        self.bitsPerSample = bitsPerSample
        self.host = endpoint.0
        self.port = endpoint.1
        self.raw = raw
    }

    public static func parse(_ data: Data) throws -> TalkbackSession {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { throw ProtectError.decoding }
        let object: [String: Any]?
        if let dict = json as? [String: Any] {
            object = (dict["data"] as? [String: Any]) ?? dict
        } else {
            object = (json as? [[String: Any]])?.first
        }
        guard let object else { throw ProtectError.decoding }
        let raw = String(String(decoding: data, as: UTF8.self).prefix(500))
        let url = string(object, ["url", "uri", "streamUrl", "talkbackUrl"]) ?? ""
        return try TalkbackSession(
            url: url,
            codec: string(object, ["codec", "typeFmt", "format"]) ?? "",
            samplingRate: integer(object, ["samplingRate", "sampleRate", "sampling_rate"]) ?? 0,
            bitsPerSample: integer(object, ["bitsPerSample", "bits_per_sample"]) ?? 16,
            raw: raw
        )
    }

    /// "rtp://192.168.1.20:7004", "udp://[fe80::1]:7004", "cam.local", "192.168.1.20" → host + port (default 7004).
    /// Strict on purpose: the answer comes from an unverified camera. Only the schemes rtp and udp (or none),
    /// and only ASCII letters, digits, dots, hyphens, colons and brackets. Escapes, zone suffixes, spaces and
    /// control characters are rejected, and the host must be an IPv4/IPv6 literal or a plain hostname.
    static func endpoint(from url: String) -> (String, UInt16)? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        var authority = Substring(trimmed)
        if let range = trimmed.range(of: "://") {
            let scheme = trimmed[..<range.lowerBound].lowercased()
            guard scheme == "rtp" || scheme == "udp" else { return nil }
            authority = trimmed[range.upperBound...]
        }
        guard !authority.isEmpty, authority.allSatisfy(allowedAuthorityCharacters.contains) else { return nil }

        let host: Substring
        let portText: Substring?
        if authority.hasPrefix("[") {
            guard let close = authority.firstIndex(of: "]") else { return nil }
            host = authority[authority.index(after: authority.startIndex)..<close]
            let rest = authority[authority.index(after: close)...]
            if rest.isEmpty {
                portText = nil
            } else if rest.first == ":" {
                portText = rest.dropFirst()
            } else {
                return nil
            }
            guard IPv6Address(String(host)) != nil else { return nil }
        } else {
            let parts = authority.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count <= 2 else { return nil }
            host = parts[0]
            portText = parts.count == 2 ? parts[1] : nil
            guard IPv4Address(String(host)) != nil || isPlainHostname(host) else { return nil }
        }

        guard let portText else { return (String(host), defaultPort) }
        guard !portText.isEmpty, portText.allSatisfy({ $0.isASCII && $0.isNumber }),
              let number = Int(portText), (1...65_535).contains(number) else { return nil }
        return (String(host), UInt16(number))
    }

    private static let allowedAuthorityCharacters = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-:[]")

    /// Dot-separated labels of ASCII letters, digits and hyphens; no empty label.
    private static func isPlainHostname(_ text: Substring) -> Bool {
        text.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
            !label.isEmpty && label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }
    }

    private static func string(_ object: [String: Any], _ keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String, !value.isEmpty { return value }
        }
        return nil
    }

    private static func integer(_ object: [String: Any], _ keys: [String]) -> Int? {
        for key in keys {
            if let value = object[key] as? Int { return value }
            // Int(exactly:) returns nil instead of trapping for values outside Int's range.
            if let value = object[key] as? Double, let number = Int(exactly: value.rounded(.towardZero)) { return number }
            if let value = object[key] as? String, let number = Int(value.trimmingCharacters(in: .whitespaces)) { return number }
        }
        return nil
    }
}
