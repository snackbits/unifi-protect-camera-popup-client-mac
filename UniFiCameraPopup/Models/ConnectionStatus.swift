import Foundation

enum ConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case outdated

    var menuLabel: String {
        switch self {
        case .disconnected: return "Getrennt"
        case .connecting: return "Verbinde…"
        case .connected: return "Verbunden"
        case .outdated: return "Veraltete App-Version"
        }
    }

    var symbolName: String {
        switch self {
        case .disconnected: return "circle.fill"
        case .connecting: return "circle.dotted"
        case .connected: return "circle.fill"
        case .outdated: return "exclamationmark.triangle.fill"
        }
    }
}
