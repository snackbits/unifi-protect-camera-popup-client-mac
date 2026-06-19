import Foundation

enum PopupPosition: String, Codable, CaseIterable, Identifiable {
    case topLeft
    case topCenter
    case topRight
    case middleLeft
    case center
    case middleRight
    case bottomLeft
    case bottomCenter
    case bottomRight

    var id: String { rawValue }

    var label: String {
        switch self {
        case .topLeft: return "Oben links"
        case .topCenter: return "Oben mitte"
        case .topRight: return "Oben rechts"
        case .middleLeft: return "Links mitte"
        case .center: return "Bildschirmmitte"
        case .middleRight: return "Rechts mitte"
        case .bottomLeft: return "Unten links"
        case .bottomCenter: return "Unten mitte"
        case .bottomRight: return "Unten rechts"
        }
    }

    /// When several popups are stacked, anchors at the bottom of the screen grow
    /// upward so the stack never runs off the bottom edge.
    var stacksUpward: Bool {
        switch self {
        case .bottomLeft, .bottomCenter, .bottomRight:
            return true
        default:
            return false
        }
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
