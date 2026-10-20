import Foundation

/// Settings that only this build knows. The installed older build shares the UserDefaults domain,
/// decodes the main settings blob and rewrites it, dropping every key it does not know. These
/// values are therefore also kept under their own key, which the older build never touches, and
/// overlaid on the main blob at load.
///
/// Per-mapping and per-action values are keyed by the entry id / action id (UUID strings) so they
/// survive the older build adding, removing or reordering entries.
public struct SettingsExtensions: Codable, Equatable, Sendable {
    public struct Mapping: Codable, Equatable, Sendable {
        public var protectCameraId: String?
        /// `TriggerKind` raw values.
        public var triggers: [String]?
        public var webhookTriggerEnabled: Bool?
        public var chimeOnOpen: Bool?
        /// Phase 5: „Name und Zeit einblenden“ (nil = not written yet → off).
        public var showNameAndTime: Bool?
        /// Phase 5: „Größe“; nil = not written yet (migrated from the main blob's width/height).
        public var size: PopupSizeOverride?
        /// Phase 5: Kameras › Ereignisse (without tokens).
        public var eventRules: EventRuleList?

        public init(
            protectCameraId: String? = nil,
            triggers: [String]? = nil,
            webhookTriggerEnabled: Bool? = nil,
            chimeOnOpen: Bool? = nil,
            showNameAndTime: Bool? = nil,
            size: PopupSizeOverride? = nil,
            eventRules: EventRuleList? = nil
        ) {
            self.protectCameraId = protectCameraId
            self.triggers = triggers
            self.webhookTriggerEnabled = webhookTriggerEnabled
            self.chimeOnOpen = chimeOnOpen
            self.showNameAndTime = showNameAndTime
            self.size = size
            self.eventRules = eventRules
        }

        private enum CodingKeys: String, CodingKey {
            case protectCameraId, triggers, webhookTriggerEnabled, chimeOnOpen
            case showNameAndTime, size, eventRules
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            protectCameraId = (try? c.decodeIfPresent(String.self, forKey: .protectCameraId)) ?? nil
            triggers = (try? c.decodeIfPresent([String].self, forKey: .triggers)) ?? nil
            webhookTriggerEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .webhookTriggerEnabled)) ?? nil
            chimeOnOpen = (try? c.decodeIfPresent(Bool.self, forKey: .chimeOnOpen)) ?? nil
            showNameAndTime = (try? c.decodeIfPresent(Bool.self, forKey: .showNameAndTime)) ?? nil
            size = (try? c.decodeIfPresent(PopupSizeOverride.self, forKey: .size)) ?? nil
            eventRules = (try? c.decodeIfPresent(EventRuleList.self, forKey: .eventRules)) ?? nil
        }
    }

    public struct Action: Codable, Equatable, Sendable {
        /// `ActionIcon` raw value.
        public var icon: String?
        public var confirmBeforeRun: Bool?
        /// Phase 5: announcement id (UUID string) the button plays; nil = no sound.
        public var soundId: String?

        public init(icon: String? = nil, confirmBeforeRun: Bool? = nil, soundId: String? = nil) {
            self.icon = icon
            self.confirmBeforeRun = confirmBeforeRun
            self.soundId = soundId
        }

        private enum CodingKeys: String, CodingKey { case icon, confirmBeforeRun, soundId }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            icon = (try? c.decodeIfPresent(String.self, forKey: .icon)) ?? nil
            confirmBeforeRun = (try? c.decodeIfPresent(Bool.self, forKey: .confirmBeforeRun)) ?? nil
            soundId = (try? c.decodeIfPresent(String.self, forKey: .soundId)) ?? nil
        }
    }

    public var protectHost: String?
    public var protectCertificateFingerprint: String?
    public var protectConsoleName: String?
    public var muteSchedule: MuteSchedule?
    public var muteShort: MuteDuration?
    public var muteLong: MuteDuration?
    public var appearance: AppearanceMode?
    public var popupLayoutMode: PopupLayoutMode?
    /// 3.1.0: volume of a compact miniature in percent (0…100); nil = not written yet → 50.
    public var miniatureVolume: Double?
    /// Mapping entry id → values.
    public var mappings: [String: Mapping]
    /// Action id → values.
    public var actions: [String: Action]

    public init(
        protectHost: String? = nil,
        protectCertificateFingerprint: String? = nil,
        protectConsoleName: String? = nil,
        muteSchedule: MuteSchedule? = nil,
        muteShort: MuteDuration? = nil,
        muteLong: MuteDuration? = nil,
        appearance: AppearanceMode? = nil,
        popupLayoutMode: PopupLayoutMode? = nil,
        miniatureVolume: Double? = nil,
        mappings: [String: Mapping] = [:],
        actions: [String: Action] = [:]
    ) {
        self.protectHost = protectHost
        self.protectCertificateFingerprint = protectCertificateFingerprint
        self.protectConsoleName = protectConsoleName
        self.muteSchedule = muteSchedule
        self.muteShort = muteShort
        self.muteLong = muteLong
        self.appearance = appearance
        self.popupLayoutMode = popupLayoutMode
        self.miniatureVolume = miniatureVolume
        self.mappings = mappings
        self.actions = actions
    }

    private enum CodingKeys: String, CodingKey {
        case protectHost, protectCertificateFingerprint, protectConsoleName
        case muteSchedule, muteShort, muteLong, appearance, popupLayoutMode, miniatureVolume, mappings, actions
    }

    /// Every field is decoded on its own: one broken value never discards the others.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        protectHost = (try? c.decodeIfPresent(String.self, forKey: .protectHost)) ?? nil
        protectCertificateFingerprint = (try? c.decodeIfPresent(String.self, forKey: .protectCertificateFingerprint)) ?? nil
        protectConsoleName = (try? c.decodeIfPresent(String.self, forKey: .protectConsoleName)) ?? nil
        muteSchedule = (try? c.decodeIfPresent(MuteSchedule.self, forKey: .muteSchedule)) ?? nil
        muteShort = (try? c.decodeIfPresent(MuteDuration.self, forKey: .muteShort)) ?? nil
        muteLong = (try? c.decodeIfPresent(MuteDuration.self, forKey: .muteLong)) ?? nil
        appearance = (try? c.decodeIfPresent(AppearanceMode.self, forKey: .appearance)) ?? nil
        popupLayoutMode = (try? c.decodeIfPresent(PopupLayoutMode.self, forKey: .popupLayoutMode)) ?? nil
        miniatureVolume = (try? c.decodeIfPresent(Double.self, forKey: .miniatureVolume)) ?? nil
        mappings = (try? c.decodeIfPresent([String: Mapping].self, forKey: .mappings)) ?? [:]
        actions = (try? c.decodeIfPresent([String: Action].self, forKey: .actions)) ?? [:]
    }

    /// Decodes stored data; missing or garbled data yields nil (the main blob is then used as is).
    public static func decode(_ data: Data?) -> SettingsExtensions? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(SettingsExtensions.self, from: data)
    }

    /// Drops entries of mappings/actions that no longer exist.
    public func pruned(validMappings: Set<String>, validActions: Set<String>) -> SettingsExtensions {
        var copy = self
        copy.mappings = mappings.filter { validMappings.contains($0.key) }
        copy.actions = actions.filter { validActions.contains($0.key) }
        return copy
    }
}
