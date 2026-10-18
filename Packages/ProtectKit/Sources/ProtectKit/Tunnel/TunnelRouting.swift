import Foundation

/// Setting „Tunnel verwenden“.
public enum TunnelMode: String, Codable, CaseIterable, Sendable {
    case automatic, always, off

    public var label: String {
        switch self {
        case .automatic: return "Automatisch"
        case .always: return "Immer"
        case .off: return "Nie"
        }
    }
}

/// How the app reaches the console right now.
public enum ProtectRoute: Equatable, Sendable {
    case direct
    case tunnel
}

/// Outcome of a direct TLS probe of the configured console address.
public enum DirectReachability: Equatable, Sendable {
    /// Answered with the pinned certificate (or any certificate while nothing is pinned yet).
    case console
    /// Something answered, but with another certificate: a foreign network that happens
    /// to use the same address (hotel router on 192.168.1.1). Never send the key there.
    case otherDevice
    case unreachable

    public static func from(presentedFingerprint: String?, pinned: String?) -> DirectReachability {
        guard let presented = presentedFingerprint else { return .unreachable }
        guard let pinned else { return .console }
        return presented == pinned ? .console : .otherDevice
    }
}

public enum RouteDecision {
    /// Only automatic mode with a configured tunnel needs a direct probe.
    public static func needsProbe(mode: TunnelMode, hasTunnel: Bool) -> Bool {
        hasTunnel && mode == .automatic
    }

    /// `direct` is ignored unless `needsProbe` is true.
    public static func decide(mode: TunnelMode, hasTunnel: Bool, direct: DirectReachability) -> ProtectRoute {
        guard hasTunnel else { return .direct }
        switch mode {
        case .off: return .direct
        case .always: return .tunnel
        case .automatic: return direct == .console ? .direct : .tunnel
        }
    }
}
