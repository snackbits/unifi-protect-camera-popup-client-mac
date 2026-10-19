import AppCore
import Foundation

/// Screen side of the popup stack; the stack always starts at the top (top left / top right).
enum PopupPosition: String, Codable, CaseIterable, Identifiable {
    case left
    case right

    var id: String { rawValue }

    var label: String {
        switch self {
        case .left: return "Links"
        case .right: return "Rechts"
        }
    }

    /// Side of the miniature stack (`PopupStackLayout.miniatureFrames`).
    var side: PopupAnchor.Horizontal {
        switch self {
        case .left: return .leading
        case .right: return .trailing
        }
    }

    /// Anchor of the full-size stack (`PopupStackLayout.frames`).
    var anchor: PopupAnchor {
        PopupAnchor(horizontal: side, vertical: .top)
    }

    /// Old nine-anchor values and unknown ones map to a side (`PopupAnchor.Horizontal.side(fromPositionRawValue:)`).
    static func migrated(rawValue: String) -> PopupPosition {
        PopupAnchor.Horizontal.side(fromPositionRawValue: rawValue) == .leading ? .left : .right
    }

    init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        self = Self.migrated(rawValue: raw)
    }

    /// Written as the old top anchors, which every build decodes: an older installed build that
    /// reads the shared settings would otherwise discard the whole settings file.
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self == .left ? "topLeft" : "topRight")
    }
}

enum ScreenTarget: String, Codable, CaseIterable, Identifiable {
    case main
    case mouse

    var id: String { rawValue }

    var label: String {
        switch self {
        case .main: return "Hauptbildschirm"
        case .mouse: return "Bildschirm mit Maus"
        }
    }
}
