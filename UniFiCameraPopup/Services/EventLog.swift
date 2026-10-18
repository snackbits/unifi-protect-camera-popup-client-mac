import AppCore
import AppKit
import Foundation

/// Recent popup triggers for the menu panel and "Zuletzt ausgelöst". Persisted separately from
/// the settings (not part of the configuration export); snapshots stay in memory.
@MainActor
final class EventLog: ObservableObject {
    static let shared = EventLog()

    @Published private(set) var history: EventHistory
    /// Snapshot taken when the event arrived, keyed by `EventRecord.id`.
    @Published private(set) var thumbnails: [UUID: NSImage] = [:]

    private let defaults = UserDefaults.standard
    private static let storageKey = "unifi.camera.popup.events"

    private init() {
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(EventHistory.self, from: data) {
            history = saved
        } else {
            history = EventHistory()
        }
    }

    func record(mapping: WebhookMapping, kindLabel: String?, date: Date) {
        let name = mapping.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let record = EventRecord(
            entryId: mapping.entryId.uuidString,
            kindLabel: kindLabel,
            cameraName: name.isEmpty ? "Kamera" : name,
            date: date
        )
        history.record(record)
        persist()

        guard let cameraId = mapping.protectCameraId else { return }
        Task {
            if let image = await ProtectSession.shared.snapshot(cameraId: cameraId, maxAge: 0) {
                thumbnails[record.id] = image
            }
            let kept = Set(history.records.map(\.id))
            thumbnails = thumbnails.filter { kept.contains($0.key) }
        }
    }

    func lastTriggered(entryId: UUID) -> Date? {
        history.lastTriggered(entry: entryId.uuidString)
    }

    /// Forgets events of removed cameras; writes only on change.
    func removeEntries(notIn ids: Set<UUID>) {
        var updated = history
        updated.removeEntries(notIn: Set(ids.map(\.uuidString)))
        guard updated != history else { return }
        history = updated
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(history) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}
