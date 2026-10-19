import Foundation

/// Which Protect RTSPS stream the popup plays, per camera (Kameras › „Bildqualität“).
/// Lower streams start faster: smaller key frames arrive sooner after connecting.
public enum StreamQuality: String, Codable, CaseIterable, Sendable {
    case high, medium, low

    public static let standard = StreamQuality.medium

    public var label: String {
        switch self {
        case .high: return "Hoch"
        case .medium: return "Mittel"
        case .low: return "Niedrig"
        }
    }

    /// Protect quality names to try, nearest first, when the camera lacks this one.
    public var fallbackOrder: [String] {
        switch self {
        case .high: return ["high", "medium", "low"]
        case .medium: return ["medium", "high", "low"]
        case .low: return ["low", "medium", "high"]
        }
    }
}
