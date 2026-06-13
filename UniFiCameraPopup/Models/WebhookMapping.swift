import Foundation

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

struct WebhookMapping: Codable, Identifiable, Equatable {
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
        crop: CameraCrop? = nil
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
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entryId = try container.decodeIfPresent(UUID.self, forKey: .entryId) ?? UUID()
        webhookId = try container.decode(String.self, forKey: .webhookId)
        rtspsURL = try container.decode(String.self, forKey: .rtspsURL)
        label = try container.decode(String.self, forKey: .label)
        positionOverride = try container.decodeIfPresent(PopupPosition.self, forKey: .positionOverride)
        width = try container.decodeIfPresent(Double.self, forKey: .width)
            ?? container.decodeIfPresent(Double.self, forKey: .widthOverride)
            ?? 480
        height = try container.decodeIfPresent(Double.self, forKey: .height)
            ?? container.decodeIfPresent(Double.self, forKey: .heightOverride)
            ?? 270
        soundEnabled = try container.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? true
        rememberZoom = try container.decodeIfPresent(Bool.self, forKey: .rememberZoom) ?? false
        savedZoom = try container.decodeIfPresent(SavedCameraZoom.self, forKey: .savedZoom)
        hotkey = try container.decodeIfPresent(CameraHotkey.self, forKey: .hotkey)
        crop = try container.decodeIfPresent(CameraCrop.self, forKey: .crop)
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
    }
}

struct TriggerEvent: Equatable {
    let webhookId: String
    let thumbnail: String?
    let alarmName: String?
    let timestamp: Date
}
