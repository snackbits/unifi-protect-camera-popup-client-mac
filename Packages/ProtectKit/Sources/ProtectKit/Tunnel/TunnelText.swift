import Foundation

/// Kind of network the Mac used for the last tunnel connection.
public enum NetworkKind: String, Codable, Sendable {
    case wifi, ethernet, cellular, other

    public var label: String {
        switch self {
        case .wifi: return "WLAN"
        case .ethernet: return "Ethernet"
        case .cellular: return "Mobilfunk"
        case .other: return "Netzwerk"
        }
    }
}

/// Lifecycle of the in-app tunnel (`TunnelController.state`).
public enum TunnelRunState: Equatable, Sendable {
    case stopped
    /// Device is up, no handshake yet.
    case starting
    case up
    /// No traffic for `TunnelLiveness.stallAfter`.
    case down
    case failed(String)
}

/// Everything the „Unterwegs“ status card can show.
public enum TunnelPhase: Equatable, Sendable {
    case off
    case home
    case connecting
    case connected
    case down
    case failed(String)

    public static func from(mode: TunnelMode, route: ProtectRoute, state: TunnelRunState) -> TunnelPhase {
        if mode == .off { return .off }
        if case .failed(let message) = state { return .failed(message) }
        guard route == .tunnel else { return .home }
        switch state {
        case .stopped, .starting: return .connecting
        case .up: return .connected
        case .down: return .down
        case .failed(let message): return .failed(message)
        }
    }
}

/// Result of „Jetzt testen“.
public enum TunnelTestOutcome: Equatable, Sendable {
    case ok
    case startFailed(String)
    case noHandshake(endpoint: String)
    case consoleSilent(host: String)
    case otherDevice
    case noConsole

    public var message: String {
        switch self {
        case .ok:
            return "Tunnel funktioniert – deine Konsole antwortet."
        case .startFailed(let reason):
            return "Der Tunnel startet nicht: \(reason)"
        case .noHandshake(let endpoint):
            return "Keine Antwort von \(endpoint). Prüfe Adresse und Port-Weiterleitung."
        case .consoleSilent(let host):
            return "Der Tunnel steht, aber die Konsole (\(host)) antwortet nicht. Liegt sie in „AllowedIPs“?"
        case .otherDevice:
            return "Hinter dem Tunnel antwortet ein anderes Gerät als deine Konsole."
        case .noConsole:
            return "Es ist noch keine Konsole eingerichtet."
        }
    }
}

public enum TunnelText {
    /// „gestern, 18:22 · über Mobilfunk“ (Vorlage, Reiter „Unterwegs“). `dayAndTime` comes
    /// from `AppCore.DisplayText.dayAndTime` so all dates in the app read the same.
    public static func lastConnection(dayAndTime: String, via kind: NetworkKind) -> String {
        "\(dayAndTime) · über \(kind.label)"
    }

    /// Status chip of the menu panel while connected: „Zu Hause“ (Vorlage) or „Unterwegs“.
    public static func connectedChip(viaTunnel: Bool) -> String {
        viaTunnel ? "Unterwegs" : "Zu Hause"
    }

    /// Title and subtitle of the status card.
    public static func status(_ phase: TunnelPhase) -> (title: String, subtitle: String) {
        switch phase {
        case .off:
            return ("Aus", "Die App verbindet sich nur direkt mit der Konsole.")
        case .home:
            return ("Bereit · gerade zu Hause", "Der Tunnel springt an, sobald die Konsole nicht direkt erreichbar ist.")
        case .connecting:
            return ("Verbinde · unterwegs", "Der Tunnel wird aufgebaut …")
        case .connected:
            return ("Verbunden · unterwegs", "Die App erreicht deine Konsole über den Tunnel.")
        case .down:
            return ("Keine Verbindung · unterwegs", "Die Gegenstelle antwortet nicht. Prüfe Internet und Port-Weiterleitung.")
        case .failed(let message):
            return ("Tunnel startet nicht", message)
        }
    }

    /// Popup notice when talkback is asked for away from home but the camera is not routed.
    public static let talkbackNotRouted = "Sprechen unterwegs nicht möglich (Kamera nicht im Tunnel)."

    /// Hint shown after an import when the console address is not routed through the tunnel.
    public static func consoleNotRouted(_ host: String) -> String {
        "Achtung: Konsole \(host) liegt nicht in „AllowedIPs“."
    }
}
