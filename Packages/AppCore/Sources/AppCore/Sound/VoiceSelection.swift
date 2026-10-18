import Foundation

/// A Piper voice plus speaker, stored in `Announcement.voiceIdentifier` as „piper:<id>#<speaker>“.
public struct PiperVoiceRef: Equatable, Hashable, Sendable {
    public static let prefix = "piper:"

    public let voiceId: String
    public let speaker: Int

    public init(voiceId: String, speaker: Int = 0) {
        self.voiceId = voiceId
        self.speaker = max(0, speaker)
    }

    /// The default for new announcements: Thorsten (medium).
    public static var standard: PiperVoiceRef { PiperVoiceRef(voiceId: PiperVoiceCatalog.bundledVoiceId) }

    /// Default speaker of a voice (neutral for Thorsten emotional).
    public init(voice: PiperVoice) {
        self.init(voiceId: voice.id, speaker: voice.defaultSpeaker)
    }

    public var identifier: String { "\(Self.prefix)\(voiceId)#\(speaker)" }

    /// nil for anything else (macOS identifiers „com.apple.…“, empty, malformed).
    public init?(identifier: String?) {
        guard let identifier, identifier.hasPrefix(Self.prefix) else { return nil }
        let body = identifier.dropFirst(Self.prefix.count)
        let parts = body.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        guard let first = parts.first, !first.isEmpty else { return nil }
        var speaker = 0
        if parts.count == 2 {
            guard let value = Int(parts[1]), value >= 0 else { return nil }
            speaker = value
        }
        self.init(voiceId: String(first), speaker: speaker)
    }

    /// The offered voice, with the speaker clamped into its range (nil = unknown or excluded voice).
    public var resolved: (voice: PiperVoice, speaker: Int)? {
        guard let voice = PiperVoiceCatalog.voice(id: voiceId) else { return nil }
        let speaker = (0..<voice.speakerCount).contains(speaker) ? speaker : voice.defaultSpeaker
        return (voice, speaker)
    }

    /// „Thorsten emotional · mittel · neutral“ / „Thorsten · mittel“; „Unbekannte Stimme“ when gone.
    public var label: String {
        guard let (voice, speaker) = resolved else { return "Unbekannte Stimme" }
        guard let speakerLabel = voice.speakerLabel(speaker) else { return voice.label }
        return "\(voice.label) · \(speakerLabel)"
    }
}

/// Which voice an announcement's audio has (Phase 6: Piper only; macOS voices are gone).
public enum AnnouncementVoice: Equatable, Sendable {
    /// Rendered by Piper with this voice.
    case piper(PiperVoiceRef)
    /// One of the shipped recordings with its original wording (made with Piper, Thorsten medium).
    case bundledRecording
    /// Rendered by a macOS voice before Phase 6: still plays, „Übernehmen“ renders it again.
    case legacyMacOS
    /// MP3 entries, or text that was never rendered.
    case none

    public static func of(_ entry: Announcement) -> AnnouncementVoice {
        guard entry.kind == .speech else { return .none }
        if entry.usesBundledRecording { return .bundledRecording }
        if let ref = PiperVoiceRef(identifier: entry.voiceIdentifier) {
            return entry.fileName == nil ? .none : .piper(ref)
        }
        return entry.fileName == nil ? .none : .legacyMacOS
    }

    /// Voice the picker starts with for this entry: its own Piper voice, else Thorsten (medium).
    public static func initialSelection(for entry: Announcement) -> PiperVoiceRef {
        if case .piper(let ref) = of(entry), ref.resolved != nil { return ref }
        if let ref = PiperVoiceRef(identifier: entry.voiceIdentifier), ref.resolved != nil { return ref }
        return .standard
    }

    /// Note under the voice field; nil when the audio already matches.
    public static func note(for entry: Announcement) -> String? {
        switch of(entry) {
        case .legacyMacOS: return "macOS (alt) – mit „Übernehmen“ neu erzeugen"
        case .piper(let ref) where ref.resolved == nil:
            return "Diese Stimme gibt es nicht mehr – mit „Übernehmen“ neu erzeugen"
        default: return nil
        }
    }

    /// „Übernehmen“ is active when text or voice differ from the entry's audio (also for every
    /// macOS-rendered entry, so it can be rendered again with Piper).
    public static func canApply(_ entry: Announcement, text: String, selection: PiperVoiceRef) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, selection.resolved != nil else { return false }
        guard entry.kind == .speech, trimmed == entry.text else { return true }
        switch of(entry) {
        case .piper(let ref): return ref != selection
        case .bundledRecording: return selection != .standard
        case .legacyMacOS, .none: return true
        }
    }
}

/// Whether a voice can speak right away (bundled / downloaded) or must be downloaded first.
public enum VoiceAvailability: Equatable, Sendable {
    case bundled
    case downloaded
    case notDownloaded
}

extension PiperVoice {
    /// „63 MB“ – whole megabytes (10^6, like Finder), at least 1.
    public var sizeText: String {
        "\(max(1, Int((Double(downloadSize) / 1_000_000).rounded()))) MB"
    }

    /// Entry of the voice field: „Thorsten · mittel – mitgeliefert“, „… – geladen“, „Kerstin · niedrig – 63 MB laden“.
    public func menuTitle(_ availability: VoiceAvailability) -> String {
        switch availability {
        case .bundled: return "\(label) – mitgeliefert"
        case .downloaded: return "\(label) – geladen"
        case .notDownloaded: return "\(label) – \(sizeText) laden"
        }
    }

    /// „Lade „Kerstin · niedrig“ … 23 von 63 MB“.
    public func progressText(received: Int64) -> String {
        let done = Int((Double(max(0, min(received, downloadSize))) / 1_000_000).rounded(.down))
        return "Lade „\(label)“ … \(done) von \(sizeText)"
    }

    /// Line under the voice field: license of the training data.
    public var licenseText: String {
        "Lizenz der Stimme: \(license.name) · \(license.dataset)"
    }

    /// The voice field lists the bundled voice first, then the catalog order.
    public static var menuOrder: [PiperVoice] {
        let bundled = PiperVoiceCatalog.bundled
        return [bundled] + PiperVoiceCatalog.offered.filter { $0.id != bundled.id }
    }
}
