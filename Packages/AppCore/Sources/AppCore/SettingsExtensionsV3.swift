import Foundation

/// Phase-5 values per camera and per button, under a key (`settingsExtensionsV3`) that the
/// installed 1.2.0 build does not know. That build knows `settingsExtensionsV2` and rewrites it –
/// like the main blob – on every launch without the Phase-5 fields, so those fields need a key of
/// their own. At load V3 wins over V2 and the main blob (`SettingsMerge`).
public struct SettingsExtensionsV3: Codable, Equatable, Sendable {
    public struct Mapping: Codable, Equatable, Sendable {
        public var showNameAndTime: Bool?
        public var size: PopupSizeOverride?
        /// Without tokens.
        public var eventRules: EventRuleList?
        /// „Bildqualität“ (2.1.0); nil = `StreamQuality.standard`.
        public var streamQuality: StreamQuality?

        public init(
            showNameAndTime: Bool? = nil,
            size: PopupSizeOverride? = nil,
            eventRules: EventRuleList? = nil,
            streamQuality: StreamQuality? = nil
        ) {
            self.showNameAndTime = showNameAndTime
            self.size = size
            self.eventRules = eventRules
            self.streamQuality = streamQuality
        }

        private enum CodingKeys: String, CodingKey { case showNameAndTime, size, eventRules, streamQuality }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            showNameAndTime = (try? c.decodeIfPresent(Bool.self, forKey: .showNameAndTime)) ?? nil
            size = (try? c.decodeIfPresent(PopupSizeOverride.self, forKey: .size)) ?? nil
            eventRules = (try? c.decodeIfPresent(EventRuleList.self, forKey: .eventRules)) ?? nil
            streamQuality = (try? c.decodeIfPresent(StreamQuality.self, forKey: .streamQuality)) ?? nil
        }
    }

    public struct Action: Codable, Equatable, Sendable {
        /// Announcement id (UUID string); nil = „Kein Ton“. The entry itself is authoritative.
        public var soundId: String?

        public init(soundId: String? = nil) {
            self.soundId = soundId
        }

        private enum CodingKeys: String, CodingKey { case soundId }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            soundId = (try? c.decodeIfPresent(String.self, forKey: .soundId)) ?? nil
        }
    }

    /// Mapping entry id → values.
    public var mappings: [String: Mapping]
    /// Action id → values.
    public var actions: [String: Action]

    public init(mappings: [String: Mapping] = [:], actions: [String: Action] = [:]) {
        self.mappings = mappings
        self.actions = actions
    }

    private enum CodingKeys: String, CodingKey { case mappings, actions }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mappings = (try? c.decodeIfPresent([String: Mapping].self, forKey: .mappings)) ?? [:]
        actions = (try? c.decodeIfPresent([String: Action].self, forKey: .actions)) ?? [:]
    }

    /// Missing or garbled data yields nil (V2 and the main blob are then used as is).
    public static func decode(_ data: Data?) -> SettingsExtensionsV3? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(SettingsExtensionsV3.self, from: data)
    }
}

/// The Phase-5 fields of one camera entry, as resolved from main blob → V2 → V3.
public struct Phase5MappingFields: Equatable, Sendable {
    public var showNameAndTime: Bool
    public var sizeOverride: PopupSizeOverride
    public var eventRules: [EventRule]

    public init(showNameAndTime: Bool, sizeOverride: PopupSizeOverride, eventRules: [EventRule]) {
        self.showNameAndTime = showNameAndTime
        self.sizeOverride = sizeOverride
        self.eventRules = eventRules
    }
}

/// Load-time precedence of the Phase-5 fields: main blob, then `settingsExtensionsV2` (only where it
/// actually carries a value – the older build rewrites it without them), then `settingsExtensionsV3`.
public enum SettingsMerge {
    public static func mapping(
        entryId: String,
        base: Phase5MappingFields,
        v2: SettingsExtensions?,
        v3: SettingsExtensionsV3?
    ) -> Phase5MappingFields {
        var fields = base
        for source in [v2?.mappings[entryId].map(Self.fields), v3?.mappings[entryId].map(Self.fields)] {
            guard let source else { continue }
            if let show = source.show { fields.showNameAndTime = show }
            if let size = source.size { fields.sizeOverride = size }
            if let rules = source.rules { fields.eventRules = rules.rules }
        }
        return fields
    }

    /// A V3 entry for the action is authoritative (no id there = „Kein Ton“); V2 only when it
    /// carries an id; otherwise the main blob's value.
    public static func soundId(actionId: String, base: UUID?, v2: SettingsExtensions?, v3: SettingsExtensionsV3?) -> UUID? {
        if let entry = v3?.actions[actionId] {
            return entry.soundId.flatMap(UUID.init(uuidString:))
        }
        if let id = v2?.actions[actionId]?.soundId.flatMap(UUID.init(uuidString:)) {
            return id
        }
        return base
    }

    /// `width`/`height` the main blob keeps for the older build: a typed size (both sides) without a
    /// crop, otherwise the current values (a crop owns them, see `saveCrop`).
    public static func legacyDimensions(
        size: PopupSizeOverride,
        hasCrop: Bool,
        width: Double,
        height: Double
    ) -> (width: Double, height: Double) {
        guard !hasCrop, let typedWidth = size.width, let typedHeight = size.height else { return (width, height) }
        let minimum = PopupSizeOverride.minimumValue
        return (max(minimum, typedWidth), max(minimum, typedHeight))
    }

    private static func fields(_ m: SettingsExtensions.Mapping) -> (show: Bool?, size: PopupSizeOverride?, rules: EventRuleList?) {
        (m.showNameAndTime, m.size, m.eventRules)
    }

    private static func fields(_ m: SettingsExtensionsV3.Mapping) -> (show: Bool?, size: PopupSizeOverride?, rules: EventRuleList?) {
        (m.showNameAndTime, m.size, m.eventRules)
    }
}
