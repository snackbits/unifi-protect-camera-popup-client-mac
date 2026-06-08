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

enum MultiAlarmBehavior: String, Codable, CaseIterable, Identifiable {
    case replace
    case extend

    var id: String { rawValue }

    var label: String {
        switch self {
        case .replace: return "Neuen Alarm ersetzen"
        case .extend: return "Timeout verlängern"
        }
    }
}
