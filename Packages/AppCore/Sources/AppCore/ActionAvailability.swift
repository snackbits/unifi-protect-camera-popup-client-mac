import Foundation

/// Popup buttons (Phase 5): a button calls a webhook, plays an announcement at the camera, or both.
public enum ActionAvailability {
    /// Saveable: a title and something to do. A typed address must be valid; it may stay
    /// empty when a sound is chosen.
    public static func isConfigured(title: String, address: String, hasValidURL: Bool, hasSound: Bool) -> Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let addressEmpty = address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return addressEmpty ? hasSound : hasValidURL
    }

    /// Shown in this popup: the webhook part always, a sound only on a camera with speaker.
    public static func isShown(hasWebhook: Bool, hasSound: Bool, canPlaySound: Bool) -> Bool {
        hasWebhook || (hasSound && canPlaySound)
    }

    public static func playsSound(hasSound: Bool, canPlaySound: Bool) -> Bool {
        hasSound && canPlaySound
    }
}
