import Foundation

/// "Popup-Layout" in Einstellungen › Erscheinungsbild.
public enum PopupLayoutMode: String, Codable, CaseIterable, Sendable {
    /// Small preview at the screen edge that grows while the pointer rests on it.
    case miniature
    /// Popups open right away at their full size (behavior before 2.x).
    case full

    public var label: String {
        switch self {
        case .miniature: return "Miniatur"
        case .full: return "Voll"
        }
    }

    /// Unknown values (written by a newer build) fall back to `.miniature`
    /// instead of failing the whole settings file.
    public init(from decoder: Decoder) throws {
        let raw = try? decoder.singleValueContainer().decode(String.self)
        self = raw.flatMap(PopupLayoutMode.init(rawValue:)) ?? .miniature
    }
}
