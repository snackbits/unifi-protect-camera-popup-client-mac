import Foundation

/// Phase 5: every announcement speaks with Anna; without Anna the best German voice.
public enum VoiceChoice {
    public static let preferredName = "Anna"

    /// What the choice needs from `AVSpeechSynthesisVoice` (testable without installed voices).
    public struct Candidate: Equatable, Sendable {
        public let identifier: String
        public let name: String
        public let language: String
        /// Higher is better (default 1, enhanced 2, premium 3).
        public let quality: Int

        public init(identifier: String, name: String, language: String, quality: Int) {
            self.identifier = identifier
            self.name = name
            self.language = language
            self.quality = quality
        }
    }

    /// Anna in her best installed quality; else the best German voice (quality, de-DE first, name).
    public static func pick(from candidates: [Candidate]) -> Candidate? {
        let german = candidates.filter { $0.language.lowercased().hasPrefix("de") }
        let ranked = german.sorted { lhs, rhs in
            if lhs.quality != rhs.quality { return lhs.quality > rhs.quality }
            let lhsDE = lhs.language.lowercased() == "de-de"
            let rhsDE = rhs.language.lowercased() == "de-de"
            if lhsDE != rhsDE { return lhsDE }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        return ranked.first { $0.name == preferredName } ?? ranked.first
    }

    /// Text of the (disabled) voice field: „Anna · macOS“.
    public static func fieldLabel(_ voice: Candidate?) -> String {
        guard let voice else { return "Keine deutsche Stimme installiert" }
        return "\(voice.name) · macOS"
    }

    /// Hint under the field when Anna is missing; nil when Anna speaks.
    public static func hint(_ voice: Candidate?) -> String? {
        guard let voice else {
            return "Lade eine deutsche Stimme unter Systemeinstellungen › Bedienungshilfen › Gesprochene Inhalte."
        }
        guard voice.name != preferredName else { return nil }
        return "Anna ist auf diesem Mac nicht installiert – es spricht „\(voice.name)“. Anna lädst du unter Systemeinstellungen › Bedienungshilfen › Gesprochene Inhalte."
    }
}
