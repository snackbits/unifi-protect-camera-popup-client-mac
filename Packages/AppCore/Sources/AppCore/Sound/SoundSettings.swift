import Foundation

/// Einstellungen › Ton. Stored on this Mac only (not part of the configuration export).
public struct SoundSettings: Codable, Equatable, Sendable {
    /// Longest file accepted for "MP3 hinzufügen …".
    public static let maxFileDuration: TimeInterval = 300
    /// Template slider position (120 of 180) = unchanged loudness.
    public static let defaultVolume = 2.0 / 3.0

    public static let bundledBinGleichDa = Announcement(
        id: UUID(uuidString: "6F0C6A52-4C4B-4E58-9B1E-2F3C1C0A0001")!,
        name: "Bin gleich da",
        kind: .speech,
        text: "Bin gleich da! Einen kleinen Moment, bitte.",
        bundledResource: "bin-gleich-da",
        duration: 2.74
    )
    public static let bundledPaket = Announcement(
        id: UUID(uuidString: "6F0C6A52-4C4B-4E58-9B1E-2F3C1C0A0002")!,
        name: "Paket bitte abstellen",
        kind: .speech,
        text: "Paket bitte abstellen.",
        bundledResource: "paket-abstellen",
        duration: 4.0
    )

    public static var bundled: [Announcement] { [bundledBinGleichDa, bundledPaket] }
    /// The shipped original an entry was made from (also after it was rendered again).
    public static func bundledOriginal(for entry: Announcement) -> Announcement? {
        guard let resource = entry.bundledResource else { return nil }
        return bundled.first { $0.bundledResource == resource }
    }

    /// The bundled voice can only say the bundled wording.
    public static func offersBundledVoice(for entry: Announcement, text: String) -> Bool {
        guard let original = bundledOriginal(for: entry) else { return false }
        return original.text == text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var announcements: [Announcement]
    /// Core Audio device UID; nil = system default input.
    public var microphoneUID: String?
    /// „Lautstärke Sprechen“, 0…1; gain = volume × 1.5 (2/3 = unchanged after the automatic gain).
    public var talkVolume: Double
    /// „Lautstärke Ansagen“, 0…1; gain = volume × 1.5 (2/3 = unchanged after normalization).
    public var announcementVolume: Double

    public init(
        announcements: [Announcement] = SoundSettings.bundled,
        microphoneUID: String? = nil,
        talkVolume: Double = SoundSettings.defaultVolume,
        announcementVolume: Double = SoundSettings.defaultVolume
    ) {
        self.announcements = announcements
        self.microphoneUID = microphoneUID
        self.talkVolume = Self.clamped(talkVolume)
        self.announcementVolume = Self.clamped(announcementVolume)
    }

    public var talkGain: Float { Float(talkVolume * 1.5) }
    public var announcementGain: Float { Float(announcementVolume * 1.5) }

    private static func clamped(_ volume: Double) -> Double {
        volume.isFinite ? min(1, max(0, volume)) : defaultVolume
    }

    public func announcement(id: UUID) -> Announcement? {
        announcements.first { $0.id == id }
    }

    public mutating func add(_ announcement: Announcement) {
        announcements.append(announcement)
    }

    public mutating func update(_ announcement: Announcement) {
        guard let index = announcements.firstIndex(where: { $0.id == announcement.id }) else { return }
        announcements[index] = announcement
    }

    /// Drag and drop in Einstellungen › Ton: `id` takes the place of `target` (the entries between
    /// move up or down by one); the popup's sound menu follows this order.
    public mutating func move(id: UUID, to target: UUID) {
        guard id != target,
              let from = announcements.firstIndex(where: { $0.id == id }),
              let to = announcements.firstIndex(where: { $0.id == target }) else { return }
        announcements.insert(announcements.remove(at: from), at: to)
    }

    /// Removes the entry and returns it (the caller deletes its file).
    @discardableResult
    public mutating func remove(id: UUID) -> Announcement? {
        guard let index = announcements.firstIndex(where: { $0.id == id }) else { return nil }
        return announcements.remove(at: index)
    }

    /// File names still referenced (everything else in the sound folder can go).
    public var referencedFiles: Set<String> {
        Set(announcements.compactMap(\.fileName))
    }

    private enum CodingKeys: String, CodingKey {
        /// `cameraVolume`: the single slider before Phase 5, read into both new ones when they are
        /// missing; still written (= `talkVolume`) for the installed older build.
        case announcements, microphoneUID, talkVolume, announcementVolume, cameraVolume
    }

    /// Lenient: broken entries or a missing list fall back to defaults. A stored `talkMode`
    /// (Phase 3) is ignored and no longer written.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = SoundSettings()
        if let lossy = try? container.decodeIfPresent([LossyAnnouncement].self, forKey: .announcements) {
            announcements = lossy.compactMap(\.value)
        } else {
            announcements = defaults.announcements
        }
        microphoneUID = (try? container.decodeIfPresent(String.self, forKey: .microphoneUID)) ?? nil
        let legacy = (try? container.decodeIfPresent(Double.self, forKey: .cameraVolume)) ?? nil
        let talk = (try? container.decodeIfPresent(Double.self, forKey: .talkVolume)) ?? nil
        let announcement = (try? container.decodeIfPresent(Double.self, forKey: .announcementVolume)) ?? nil
        talkVolume = Self.clamped(talk ?? legacy ?? Self.defaultVolume)
        announcementVolume = Self.clamped(announcement ?? legacy ?? Self.defaultVolume)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(announcements, forKey: .announcements)
        try container.encodeIfPresent(microphoneUID, forKey: .microphoneUID)
        try container.encode(talkVolume, forKey: .talkVolume)
        try container.encode(announcementVolume, forKey: .announcementVolume)
        // The installed 1.2.0 build only knows the single slider: give it the talk volume so it
        // keeps a sane value. Decoding prefers the new keys, so this never overrides them.
        try container.encode(talkVolume, forKey: .cameraVolume)
    }

    private struct LossyAnnouncement: Decodable {
        let value: Announcement?
        init(from decoder: Decoder) throws {
            value = try? Announcement(from: decoder)
        }
    }
}
