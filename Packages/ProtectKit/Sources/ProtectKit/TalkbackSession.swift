import Foundation

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

    /// "rtp://192.168.1.20:7004", "udp://[fe80::1]:7004", "192.168.1.20" → host + port (default 7004).
    static func endpoint(from url: String) -> (String, UInt16)? {
        var trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.contains("://") { trimmed = "udp://" + trimmed }
        guard let comps = URLComponents(string: trimmed), let rawHost = comps.host else { return nil }
        let host = rawHost.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        guard !host.isEmpty else { return nil }
        guard let port = comps.port else { return (host, defaultPort) }
        guard (1...65_535).contains(port) else { return nil }
        return (host, UInt16(port))
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
            if let value = object[key] as? Double, value.isFinite { return Int(value) }
            if let value = object[key] as? String, let number = Int(value.trimmingCharacters(in: .whitespaces)) { return number }
        }
        return nil
    }
}
