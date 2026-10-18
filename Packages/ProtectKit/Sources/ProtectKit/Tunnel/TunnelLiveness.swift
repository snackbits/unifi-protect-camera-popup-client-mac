import Foundation

/// Detects a tunnel outage and its end from periodic `WgStatus` samples.
///
/// While the app runs, the events WebSocket pings every 30 s, so the tunnel
/// receives something at least that often. No received byte for `stallAfter`
/// seconds counts as an outage. The first received byte afterwards is the
/// recovery: then every relayed TCP connection must be rebuilt, because a
/// gVisor TCP connection that lived through a long blackout can stay stuck.
public struct TunnelLiveness: Sendable {
    public enum Event: Equatable, Sendable {
        case none
        case wentDown
        case recovered
    }

    public let stallAfter: TimeInterval
    public private(set) var isDown = false
    private var lastRx: Int64?
    private var lastChange: Date?

    public init(stallAfter: TimeInterval = 75) {
        self.stallAfter = stallAfter
    }

    public mutating func observe(rxBytes: Int64, at now: Date) -> Event {
        guard let previous = lastRx, let changed = lastChange else {
            lastRx = rxBytes
            lastChange = now
            return .none
        }
        if rxBytes != previous {
            lastRx = rxBytes
            lastChange = now
            if isDown {
                isDown = false
                return .recovered
            }
            return .none
        }
        if !isDown, now.timeIntervalSince(changed) >= stallAfter {
            isDown = true
            return .wentDown
        }
        return .none
    }
}
