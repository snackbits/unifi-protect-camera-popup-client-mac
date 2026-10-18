import Foundation

public struct ProtectTrigger: Equatable, Sendable {
    public let eventId: String
    public let cameraId: String
    public let kinds: Set<TriggerKind>
    public let start: Date
}

public enum EventMessage {
    private struct Envelope: Decodable {
        let type: String
        let item: Item
    }
    private struct Item: Decodable {
        let id: String?
        let type: String?
        let start: Double?
        let device: String?
        let smartDetectTypes: [String]?
    }

    /// One `events` frame as the tracker needs it.
    public enum Frame: Equatable, Sendable {
        /// A new camera event. `kinds` may be empty: a smart detection can arrive with
        /// `smartDetectTypes: []` and get its types in a later update.
        case add(eventId: String, cameraId: String, kinds: Set<TriggerKind>, start: Date)
        /// A later update carrying `smartDetectTypes` (updates carry no `device`).
        case update(eventId: String, kinds: Set<TriggerKind>)
    }

    /// Returns a trigger for new camera events (`add`) with at least one known kind, nil for
    /// everything else. Use `EventTracker` to also follow kinds arriving in updates.
    public static func parse(_ data: Data) -> ProtectTrigger? {
        guard case let .add(id, camera, kinds, start)? = frame(data), !kinds.isEmpty else { return nil }
        return ProtectTrigger(eventId: id, cameraId: camera, kinds: kinds, start: start)
    }

    /// `add` of a camera event of a known type, or an `update` with `smartDetectTypes`; nil otherwise.
    public static func frame(_ data: Data) -> Frame? {
        guard let env = try? JSONDecoder().decode(Envelope.self, from: data),
              let id = env.item.id else { return nil }

        switch env.type {
        case "add":
            guard let camera = env.item.device, let type = env.item.type else { return nil }
            let kinds: Set<TriggerKind>
            switch type {
            case "ring":
                kinds = [.ring]
            case "motion":
                kinds = [.motion]
            case "smartDetectZone", "smartDetectLine", "smartAudioDetect":
                kinds = smartKinds(env.item.smartDetectTypes)
            default:
                return nil
            }
            let start = Date(timeIntervalSince1970: (env.item.start ?? Date().timeIntervalSince1970 * 1000) / 1000)
            return .add(eventId: id, cameraId: camera, kinds: kinds, start: start)
        case "update":
            guard let types = env.item.smartDetectTypes else { return nil }
            return .update(eventId: id, kinds: smartKinds(types))
        default:
            return nil
        }
    }

    private static func smartKinds(_ types: [String]?) -> Set<TriggerKind> {
        Set((types ?? []).compactMap(TriggerKind.init(wireValue:)))
    }
}

/// A trigger with only the kinds not seen before for its event, plus those seen earlier.
public struct TrackedTrigger: Equatable, Sendable {
    /// `kinds` = newly seen kinds only (never empty).
    public let trigger: ProtectTrigger
    /// Kinds of the same event reported before this frame.
    public let previousKinds: Set<TriggerKind>
}

/// Follows the last `capacity` events from their `add` through later `update`s, so kinds that are
/// only filled in by an update (person → person + vehicle, or an `add` with no types yet) still
/// reach event rules and popups – each kind once per event. Replaces `EventDeduplicator` for the
/// events socket: a repeated `add` yields nothing new either.
public struct EventTracker {
    private struct Entry {
        let cameraId: String
        let start: Date
        var kinds: Set<TriggerKind>
    }

    private var entries: [String: Entry] = [:]
    private var order: [String] = []
    private let capacity: Int

    public init(capacity: Int = 200) { self.capacity = max(1, capacity) }

    /// Number of events currently remembered (bounded by `capacity`).
    public var count: Int { entries.count }

    public mutating func ingest(_ data: Data) -> TrackedTrigger? {
        guard let frame = EventMessage.frame(data) else { return nil }
        return ingest(frame)
    }

    public mutating func ingest(_ frame: EventMessage.Frame) -> TrackedTrigger? {
        let eventId: String
        let kinds: Set<TriggerKind>
        switch frame {
        case let .add(id, camera, addKinds, start):
            if entries[id] == nil {
                entries[id] = Entry(cameraId: camera, start: start, kinds: [])
                order.append(id)
                if order.count > capacity {
                    entries[order.removeFirst()] = nil
                }
            }
            eventId = id
            kinds = addKinds
        case let .update(id, updateKinds):
            // An update for an event we never saw added (or evicted) carries no camera: ignore.
            guard entries[id] != nil else { return nil }
            eventId = id
            kinds = updateKinds
        }
        guard var entry = entries[eventId] else { return nil }
        let previous = entry.kinds
        let new = kinds.subtracting(previous)
        guard !new.isEmpty else { return nil }
        entry.kinds.formUnion(new)
        entries[eventId] = entry
        return TrackedTrigger(
            trigger: ProtectTrigger(eventId: eventId, cameraId: entry.cameraId, kinds: new, start: entry.start),
            previousKinds: previous
        )
    }
}

/// Remembers the last `capacity` event ids so repeated `add` frames do not re-trigger.
public struct EventDeduplicator {
    private var order: [String] = []
    private var seen: Set<String> = []
    private let capacity: Int

    public init(capacity: Int = 200) { self.capacity = capacity }

    public mutating func isNew(_ eventId: String) -> Bool {
        guard !seen.contains(eventId) else { return false }
        seen.insert(eventId)
        order.append(eventId)
        if order.count > capacity {
            seen.remove(order.removeFirst())
        }
        return true
    }
}
