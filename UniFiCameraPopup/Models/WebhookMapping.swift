import Foundation
import ProtectKit

struct SavedCameraZoom: Codable, Equatable {
    var scale: Double
    var panOffsetX: Double
    var panOffsetY: Double
}

/// Normalized crop region (0–1) relative to the full video frame at 1× zoom.
struct CameraCrop: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    /// Window dimensions before the crop was applied; restored when the crop is removed.
    var originalWidth: Double
    var originalHeight: Double
}

extension CodingUserInfoKey {
    /// `true` when bearer tokens of camera actions should be written in plain
    /// text (configuration export). Otherwise they live in the keychain.
    static let includeActionTokens = CodingUserInfoKey(rawValue: "includeActionTokens")!
    /// `Set<UUID>` of action ids whose token must stay in plain text because
    /// the keychain refused to store it (prevents losing the token).
    static let plaintextActionTokenIDs = CodingUserInfoKey(rawValue: "plaintextActionTokenIDs")!
}

/// Symbol of a popup button (template sheet: door, bulb, house, bolt).
enum ActionIcon: String, Codable, CaseIterable, Identifiable {
    case door
    case bulb
    case house
    case bolt

    var id: String { rawValue }

    var label: String {
        switch self {
        case .door: return "Tür"
        case .bulb: return "Licht"
        case .house: return "Haus"
        case .bolt: return "Blitz"
        }
    }

    var templateIcon: TemplateIcon {
        switch self {
        case .door: return .actionDoor
        case .bulb: return .actionBulb
        case .house: return .actionHouse
        case .bolt: return .actionBolt
        }
    }
}

/// A user-defined button shown in the popup that calls a webhook (e.g. "Tür öffnen").
struct CameraAction: Codable, Identifiable, Equatable {
    enum Method: String, Codable, CaseIterable, Identifiable {
        case get = "GET"
        case post = "POST"

        var id: String { rawValue }
    }

    var id: UUID
    var title: String
    var url: String
    var method: Method
    /// Sent as `Authorization: Bearer <token>` when not empty.
    var bearerToken: String
    /// Symbol in the popup's button pill.
    var icon: ActionIcon
    /// Ask before calling the webhook (e.g. opening a door).
    var confirmBeforeRun: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case url
        case method
        case bearerToken
        case icon
        case confirmBeforeRun
    }

    init(
        id: UUID = UUID(),
        title: String = "",
        url: String = "",
        method: Method = .post,
        bearerToken: String = "",
        icon: ActionIcon = .bolt,
        confirmBeforeRun: Bool = false
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.method = method
        self.bearerToken = bearerToken
        self.icon = icon
        self.confirmBeforeRun = confirmBeforeRun
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        title = (try? container.decodeIfPresent(String.self, forKey: .title)) ?? ""
        url = (try? container.decodeIfPresent(String.self, forKey: .url)) ?? ""
        method = (try? container.decodeIfPresent(Method.self, forKey: .method)) ?? .post
        bearerToken = (try? container.decodeIfPresent(String.self, forKey: .bearerToken)) ?? ""
        icon = (try? container.decodeIfPresent(ActionIcon.self, forKey: .icon)) ?? .bolt
        confirmBeforeRun = (try? container.decodeIfPresent(Bool.self, forKey: .confirmBeforeRun)) ?? false
    }

    /// The bearer token is only encoded when explicitly requested (export or
    /// keychain fallback); normally `SettingsStore` keeps it in the keychain.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(url, forKey: .url)
        try container.encode(method, forKey: .method)
        try container.encode(icon, forKey: .icon)
        try container.encode(confirmBeforeRun, forKey: .confirmBeforeRun)

        let includeAll = encoder.userInfo[.includeActionTokens] as? Bool == true
        let plaintextIDs = encoder.userInfo[.plaintextActionTokenIDs] as? Set<UUID> ?? []
        if !bearerToken.isEmpty, includeAll || plaintextIDs.contains(id) {
            try container.encode(bearerToken, forKey: .bearerToken)
        }
    }

    var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The parsed URL, if it is a valid http(s) URL with a host.
    var requestURL: URL? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: trimmed),
              let scheme = parsed.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              parsed.host?.isEmpty == false else { return nil }
        return parsed
    }

    /// Only fully configured actions are shown in the popup.
    var isConfigured: Bool {
        !trimmedTitle.isEmpty && requestURL != nil
    }
}

struct WebhookMapping: Codable, Identifiable, Equatable {
    /// Maximum number of action buttons per camera.
    static let maxActions = 3

    var id: UUID { entryId }
    var entryId: UUID
    var webhookId: String
    var rtspsURL: String
    var label: String
    var positionOverride: PopupPosition?
    var width: Double
    var height: Double
    var soundEnabled: Bool
    /// When enabled, the last zoom/pan state is restored the next time this camera's popup opens.
    var rememberZoom: Bool
    var savedZoom: SavedCameraZoom?
    var hotkey: CameraHotkey?
    var crop: CameraCrop?
    var actions: [CameraAction]
    /// Protect camera id (Integration API). nil = legacy webhook/RTSP-only entry.
    var protectCameraId: String?
    /// Protect events that open this camera's popup.
    var triggers: Set<TriggerKind>
    /// Hidden option: also open the popup when the relay server receives `webhookId`.
    var webhookTriggerEnabled: Bool
    /// "Hinweiston beim Öffnen": system sound when a triggered popup opens.
    var chimeOnOpen: Bool

    enum CodingKeys: String, CodingKey {
        case entryId
        case webhookId
        case rtspsURL
        case label
        case positionOverride
        case width
        case height
        case soundEnabled
        case rememberZoom
        case savedZoom
        case hotkey
        case crop
        case actions
        case protectCameraId
        case triggers
        case webhookTriggerEnabled
        case chimeOnOpen
        case widthOverride
        case heightOverride
    }

    init(
        entryId: UUID = UUID(),
        webhookId: String = "",
        rtspsURL: String = "",
        label: String = "",
        positionOverride: PopupPosition? = nil,
        width: Double = 480,
        height: Double = 270,
        soundEnabled: Bool = true,
        rememberZoom: Bool = false,
        savedZoom: SavedCameraZoom? = nil,
        hotkey: CameraHotkey? = nil,
        crop: CameraCrop? = nil,
        actions: [CameraAction] = [],
        protectCameraId: String? = nil,
        triggers: Set<TriggerKind> = [.ring, .person],
        webhookTriggerEnabled: Bool = false,
        chimeOnOpen: Bool = false
    ) {
        self.entryId = entryId
        self.webhookId = webhookId
        self.rtspsURL = rtspsURL
        self.label = label
        self.positionOverride = positionOverride
        self.width = width
        self.height = height
        self.soundEnabled = soundEnabled
        self.rememberZoom = rememberZoom
        self.savedZoom = savedZoom
        self.hotkey = hotkey
        self.crop = crop
        self.actions = actions
        self.protectCameraId = protectCameraId
        self.triggers = triggers
        self.webhookTriggerEnabled = webhookTriggerEnabled
        self.chimeOnOpen = chimeOnOpen
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entryId = try container.decodeIfPresent(UUID.self, forKey: .entryId) ?? UUID()
        webhookId = try container.decode(String.self, forKey: .webhookId)
        rtspsURL = try container.decode(String.self, forKey: .rtspsURL)
        label = try container.decode(String.self, forKey: .label)
        width = try container.decodeIfPresent(Double.self, forKey: .width)
            ?? container.decodeIfPresent(Double.self, forKey: .widthOverride)
            ?? 480
        height = try container.decodeIfPresent(Double.self, forKey: .height)
            ?? container.decodeIfPresent(Double.self, forKey: .heightOverride)
            ?? 270
        soundEnabled = try container.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? true
        rememberZoom = try container.decodeIfPresent(Bool.self, forKey: .rememberZoom) ?? false

        // Optional sub-objects are decoded leniently: if a future build changes
        // one of their schemas, an old, now-incompatible value must only reset
        // that single field – not throw and discard the whole mapping (which,
        // via the array/PersistedSettings decode, would wipe the entire config).
        positionOverride = (try? container.decodeIfPresent(PopupPosition.self, forKey: .positionOverride)) ?? nil
        savedZoom = (try? container.decodeIfPresent(SavedCameraZoom.self, forKey: .savedZoom)) ?? nil
        hotkey = (try? container.decodeIfPresent(CameraHotkey.self, forKey: .hotkey)) ?? nil
        crop = (try? container.decodeIfPresent(CameraCrop.self, forKey: .crop)) ?? nil
        actions = (try? container.decodeIfPresent([CameraAction].self, forKey: .actions)) ?? []
        protectCameraId = (try? container.decodeIfPresent(String.self, forKey: .protectCameraId)) ?? nil
        triggers = Set((try? container.decodeIfPresent([TriggerKind].self, forKey: .triggers)) ?? [.ring, .person])
        // Legacy entries were webhook-driven: keep them working.
        webhookTriggerEnabled = (try? container.decodeIfPresent(Bool.self, forKey: .webhookTriggerEnabled))
            ?? !webhookId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        chimeOnOpen = (try? container.decodeIfPresent(Bool.self, forKey: .chimeOnOpen)) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(entryId, forKey: .entryId)
        try container.encode(webhookId, forKey: .webhookId)
        try container.encode(rtspsURL, forKey: .rtspsURL)
        try container.encode(label, forKey: .label)
        try container.encodeIfPresent(positionOverride, forKey: .positionOverride)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(soundEnabled, forKey: .soundEnabled)
        try container.encode(rememberZoom, forKey: .rememberZoom)
        try container.encodeIfPresent(savedZoom, forKey: .savedZoom)
        try container.encodeIfPresent(hotkey, forKey: .hotkey)
        try container.encodeIfPresent(crop, forKey: .crop)
        try container.encode(actions, forKey: .actions)
        try container.encodeIfPresent(protectCameraId, forKey: .protectCameraId)
        try container.encode(TriggerKind.ordered.filter(triggers.contains), forKey: .triggers)
        try container.encode(webhookTriggerEnabled, forKey: .webhookTriggerEnabled)
        try container.encode(chimeOnOpen, forKey: .chimeOnOpen)
    }
}

extension WebhookMapping {
    /// A popup can open: a manual RTSP URL is set or a Protect camera is linked.
    var hasStreamSource: Bool {
        !rtspsURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || protectCameraId != nil
    }
}

struct TriggerEvent: Equatable {
    let webhookId: String
    let thumbnail: String?
    let alarmName: String?
    let timestamp: Date
    /// Set for Protect events: the mapping entry to show.
    var mappingId: UUID? = nil
    var kinds: Set<TriggerKind> = []
}
