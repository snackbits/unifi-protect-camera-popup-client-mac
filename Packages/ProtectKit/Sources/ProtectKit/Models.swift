import Foundation

public struct ProtectMetaInfo: Decodable, Equatable, Sendable {
    public let applicationVersion: String
}

public struct ProtectCamera: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let modelName: String?
    public let isConnected: Bool
    public let hasSpeaker: Bool
    public let hasMic: Bool
    /// What this camera can detect at all.
    public let supportedTriggers: Set<TriggerKind>
    /// What is currently switched on in Protect for this camera.
    public let enabledTriggers: Set<TriggerKind>

    private enum CodingKeys: String, CodingKey {
        case id, name, type, state, mac, lcdMessage, featureFlags, smartDetectSettings
    }
    private struct FeatureFlags: Decodable {
        var hasSpeaker: Bool?
        var hasMic: Bool?
        var smartDetectTypes: [String]?
        var smartDetectAudioTypes: [String]?
    }
    private struct SmartSettings: Decodable {
        var objectTypes: [String]?
        var audioTypes: [String]?
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        let mac = (try? c.decodeIfPresent(String.self, forKey: .mac)) ?? nil
        let rawName = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? nil
        name = rawName?.isEmpty == false ? rawName! : "Kamera \(mac ?? id)"
        modelName = (try? c.decodeIfPresent(String.self, forKey: .type)) ?? nil
        isConnected = ((try? c.decodeIfPresent(String.self, forKey: .state)) ?? nil) == "CONNECTED"

        let flags = (try? c.decodeIfPresent(FeatureFlags.self, forKey: .featureFlags)) ?? nil
        hasSpeaker = flags?.hasSpeaker ?? false
        hasMic = flags?.hasMic ?? false

        // Only doorbells carry an LCD message; `"lcdMessage": null` on other models is not one.
        let hasLcdMessage = c.contains(.lcdMessage) && (try? c.decodeNil(forKey: .lcdMessage)) == false
        let isDoorbell = hasLcdMessage
            || (modelName?.localizedCaseInsensitiveContains("doorbell") ?? false)
        let smart = ((flags?.smartDetectTypes ?? []) + (flags?.smartDetectAudioTypes ?? []))
            .compactMap(TriggerKind.init(wireValue:))
        var supported = Set(smart).union([.motion])
        if isDoorbell { supported.insert(.ring) }
        // Every object kind can also be reported crossing a line (if lines are set up in Protect).
        supported.formUnion(supported.compactMap(\.lineVariant))
        supportedTriggers = supported

        let settings = (try? c.decodeIfPresent(SmartSettings.self, forKey: .smartDetectSettings)) ?? nil
        let enabledSmart = ((settings?.objectTypes ?? []) + (settings?.audioTypes ?? []))
            .compactMap(TriggerKind.init(wireValue:))
        var enabled = Set(enabledSmart).union([.motion])
        if isDoorbell { enabled.insert(.ring) }
        enabled.formUnion(enabled.compactMap(\.lineVariant))
        enabledTriggers = enabled.intersection(supported)
    }
}

public struct RTSPSStreams: Decodable, Equatable, Sendable {
    /// Quality ("high", "medium", "low", "package", …) → rtsps URL. Nulls dropped.
    public let urls: [String: String]

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode([String: String?].self)
        urls = raw.compactMapValues { $0 }
    }

    public var preferred: String? {
        urls["high"] ?? urls["medium"] ?? urls["low"]
    }

    /// First quality of `order` the camera has a URL for (e.g. `["medium", "high", "low"]`).
    public func url(in order: [String]) -> String? {
        order.lazy.compactMap { urls[$0] }.first
    }
}
