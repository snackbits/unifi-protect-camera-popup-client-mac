import Foundation

/// One entry of "Ansagen für „Ton abspielen“": an MP3 file or a text spoken by a voice.
public struct Announcement: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case file
        case speech
    }

    public var id: UUID
    public var name: String
    public var kind: Kind
    /// Spoken text (speech only).
    public var text: String
    /// macOS voice (`AVSpeechSynthesisVoice.identifier`); nil = the bundled recording's voice.
    public var voiceIdentifier: String?
    /// Audio in the app's sound folder: the copied MP3 or the rendered speech.
    public var fileName: String?
    /// Bundled MP3 in the app (resource name without extension), used while `fileName` is nil.
    public var bundledResource: String?
    /// Seconds; 0 = unknown.
    public var duration: TimeInterval

    public init(
        id: UUID = UUID(),
        name: String,
        kind: Kind,
        text: String = "",
        voiceIdentifier: String? = nil,
        fileName: String? = nil,
        bundledResource: String? = nil,
        duration: TimeInterval = 0
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.text = text
        self.voiceIdentifier = voiceIdentifier
        self.fileName = fileName
        self.bundledResource = bundledResource
        self.duration = duration
    }

    /// Badge in Einstellungen › Ton ("MP3" / "KI-STIMME").
    public var badge: String { kind == .file ? "MP3" : "KI-STIMME" }
    /// Tag in the popup's sound menu ("MP3" / "KI-Stimme").
    public var menuTag: String { kind == .file ? "MP3" : "KI-Stimme" }
    /// The bundled voice is only valid for the bundled wording.
    public var usesBundledRecording: Bool { bundledResource != nil && fileName == nil }

    /// Name still follows the text (new entries, unchanged suggestions): renaming it is automatic.
    public var hasAutomaticName: Bool {
        name == Announcement.newName || (kind == .speech && name == Announcement.suggestedName(forText: text))
    }

    public static let newName = "Neue Ansage"

    /// "0:03" – rounded to whole seconds, at least 0:01; "–:–" when unknown.
    public static func lengthText(_ duration: TimeInterval) -> String {
        guard duration.isFinite, duration > 0 else { return "–:–" }
        let seconds = max(1, Int(duration.rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// List name for a text announcement: first sentence, without end punctuation, at most 32 characters.
    public static func suggestedName(forText text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return newName }
        let firstSentence = trimmed.split(whereSeparator: { ".!?\n".contains($0) }).first.map(String.init) ?? trimmed
        let clean = firstSentence.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !clean.isEmpty else { return newName }
        guard clean.count > 32 else { return clean }
        return String(clean.prefix(31)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// List name for an added file: file name without extension.
    public static func suggestedName(forFile url: URL) -> String {
        let base = url.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return base.isEmpty ? newName : base
    }
}
