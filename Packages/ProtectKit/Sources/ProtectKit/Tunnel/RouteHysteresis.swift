import Foundation

/// Keeps a single probe result from flipping the route: the app switches between
/// direct and tunnel only after `required` consecutive results agree on the other route.
/// A result that agrees with the current route clears the pending candidate.
public struct RouteHysteresis: Sendable {
    public let required: Int
    public private(set) var candidate: ProtectRoute?
    private var count = 0

    public init(required: Int = 2) {
        self.required = max(1, required)
    }

    /// Feeds one probe-based decision. Returns the route to switch to, nil while `current` stays.
    public mutating func feed(_ wanted: ProtectRoute, current: ProtectRoute) -> ProtectRoute? {
        guard wanted != current else {
            reset()
            return nil
        }
        if candidate == wanted {
            count += 1
        } else {
            candidate = wanted
            count = 1
        }
        guard count >= required else { return nil }
        reset()
        return wanted
    }

    public mutating func reset() {
        candidate = nil
        count = 0
    }
}
