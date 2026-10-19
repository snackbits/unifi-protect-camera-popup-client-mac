import Foundation

/// One popup trigger as shown in the menu panel ("Klingel / Haustür / 10:12").
public struct EventRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    /// Mapping entry id (UUID string).
    public let entryId: String
    /// "Klingel", "Person" …; nil for webhook triggers.
    public let kindLabel: String?
    public let cameraName: String
    public let date: Date

    public init(id: UUID = UUID(), entryId: String, kindLabel: String?, cameraName: String, date: Date) {
        self.id = id
        self.entryId = entryId
        self.kindLabel = kindLabel
        self.cameraName = cameraName
        self.date = date
    }

    /// First line in the menu panel.
    public var title: String {
        kindLabel ?? "Webhook"
    }
}

/// The most recent triggers, newest first, capped at `capacity`.
public struct EventHistory: Codable, Equatable, Sendable {
    public static let capacity = 20

    public private(set) var records: [EventRecord]

    public init(records: [EventRecord] = []) {
        self.records = Array(records.sorted { $0.date > $1.date }.prefix(Self.capacity))
    }

    private enum CodingKeys: String, CodingKey { case records }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let records = (try? container.decodeIfPresent([EventRecord].self, forKey: .records)) ?? []
        self.init(records: records)
    }

    public mutating func record(_ record: EventRecord) {
        let index = records.firstIndex { $0.date <= record.date } ?? records.endIndex
        records.insert(record, at: index)
        if records.count > Self.capacity {
            records.removeLast(records.count - Self.capacity)
        }
    }

    public func latest(_ count: Int) -> [EventRecord] {
        Array(records.prefix(max(count, 0)))
    }

    public func lastTriggered(entry: String) -> Date? {
        records.first { $0.entryId == entry }?.date
    }

    public mutating func removeEntries(notIn validEntries: Set<String>) {
        records.removeAll { !validEntries.contains($0.entryId) }
    }
}
