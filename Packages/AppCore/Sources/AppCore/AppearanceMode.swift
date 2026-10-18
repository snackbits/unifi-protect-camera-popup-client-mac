import AppKit

/// "Erscheinungsbild" in Einstellungen › Allgemein.
public enum AppearanceMode: String, Codable, CaseIterable, Sendable {
    case system
    case light
    case dark

    /// Segment titles, in template order.
    public var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Hell"
        case .dark: return "Dunkel"
        }
    }

    /// Value for `NSApp.appearance`; nil follows the system.
    public var appearanceName: NSAppearance.Name? {
        switch self {
        case .system: return nil
        case .light: return .aqua
        case .dark: return .darkAqua
        }
    }

    /// Unknown values (written by a newer build) fall back to `.system`
    /// instead of failing the whole settings file.
    public init(from decoder: Decoder) throws {
        let raw = try? decoder.singleValueContainer().decode(String.self)
        self = raw.flatMap(AppearanceMode.init(rawValue:)) ?? .system
    }
}
