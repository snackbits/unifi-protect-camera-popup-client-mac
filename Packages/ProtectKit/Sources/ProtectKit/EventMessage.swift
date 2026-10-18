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

    /// Returns a trigger for new camera events (`add`), nil for everything else.
    public static func parse(_ data: Data) -> ProtectTrigger? {
        guard let env = try? JSONDecoder().decode(Envelope.self, from: data),
              env.type == "add",
              let id = env.item.id,
              let camera = env.item.device,
              let type = env.item.type else { return nil }

        let kinds: Set<TriggerKind>
        switch type {
        case "ring":
            kinds = [.ring]
        case "motion":
            kinds = [.motion]
        case "smartDetectZone", "smartDetectLine", "smartAudioDetect":
            kinds = Set((env.item.smartDetectTypes ?? []).compactMap(TriggerKind.init(wireValue:)))
        default:
            return nil
        }
        guard !kinds.isEmpty else { return nil }

        let start = Date(timeIntervalSince1970: (env.item.start ?? Date().timeIntervalSince1970 * 1000) / 1000)
        return ProtectTrigger(eventId: id, cameraId: camera, kinds: kinds, start: start)
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
