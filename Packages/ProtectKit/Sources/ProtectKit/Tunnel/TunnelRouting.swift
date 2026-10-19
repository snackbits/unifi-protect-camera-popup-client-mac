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
        guard let pinned, !pinned.isEmpty else { return .console }
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

    /// An address other than the configured console (set-up, „Ändern …“) is probed directly
    /// on its own: the current route only describes the configured address.
    public static func needsCandidateProbe(mode: TunnelMode, hasTunnel: Bool, isConfiguredHost: Bool) -> Bool {
        !isConfiguredHost && needsProbe(mode: mode, hasTunnel: hasTunnel)
    }

    /// Route for checking `candidate` before it is saved. The configured address keeps
    /// `current`; another one is direct when it answered a direct probe (at home: the same
    /// trust rules as a first set-up), else the tunnel. `answered` is ignored unless
    /// `needsCandidateProbe` is true.
    public static func decideCandidate(mode: TunnelMode, hasTunnel: Bool, isConfiguredHost: Bool,
                                       current: ProtectRoute, answered: Bool) -> ProtectRoute {
        if isConfiguredHost { return current }
        guard hasTunnel else { return .direct }
        switch mode {
        case .off: return .direct
        case .always: return .tunnel
        case .automatic: return answered ? .direct : .tunnel
        }
    }

    /// Whether the set-up must show a console's fingerprint for explicit confirmation before the
    /// API key is sent there. A direct answer alone does not prove "at home": away, a foreign
    /// router can answer on the same address (192.168.1.1 in a hotel).
    /// - A pin exists: only for another address than the configured console (unchanged rule).
    /// - No pin, tunnel configured: always – the app may be away, no trust on first use.
    /// - No pin, no tunnel: trust on first use, as in a first set-up at home.
    public static func requiresFingerprintConfirmation(hasTunnel: Bool, isConfiguredHost: Bool,
                                                       pinned: String?, confirmed: Bool) -> Bool {
        if confirmed { return false }
        if let pinned, !pinned.isEmpty { return !isConfiguredHost }
        return hasTunnel
    }
}
