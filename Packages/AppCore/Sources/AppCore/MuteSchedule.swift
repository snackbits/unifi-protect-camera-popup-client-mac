import Foundation

/// Global and per-camera mutes. Ends are absolute dates, so a mute survives an app restart
/// and an end that passed while the app was quit simply no longer counts.
public struct MuteSchedule: Codable, Equatable, Sendable {
    public struct CameraMute: Equatable, Sendable {
        public let entry: String
        public let until: Date
    }

    public private(set) var globalUntil: Date?
    /// Mapping entry id (UUID string) → end of that camera's mute.
    public private(set) var cameras: [String: Date]

    public init(globalUntil: Date? = nil, cameras: [String: Date] = [:]) {
        self.globalUntil = globalUntil
        self.cameras = cameras
    }

    private enum CodingKeys: String, CodingKey { case globalUntil, cameras }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        globalUntil = (try? container.decodeIfPresent(Date.self, forKey: .globalUntil)) ?? nil
        cameras = (try? container.decodeIfPresent([String: Date].self, forKey: .cameras)) ?? [:]
    }

    /// Settings written before per-camera muting only stored a global `muteUntil`.
    public static func migrated(stored: MuteSchedule?, legacyGlobalUntil: Date?) -> MuteSchedule {
        stored ?? MuteSchedule(globalUntil: legacyGlobalUntil)
    }

    public func globalEnd(at now: Date) -> Date? {
        guard let globalUntil, globalUntil > now else { return nil }
        return globalUntil
    }

    public func isGloballyMuted(at now: Date) -> Bool {
        globalEnd(at: now) != nil
    }

    public func cameraMuteEnd(entry: String, at now: Date) -> Date? {
        guard let end = cameras[entry], end > now else { return nil }
        return end
    }

    /// True when the camera must not open a popup: muted on its own or globally.
    public func isMuted(entry: String, at now: Date) -> Bool {
        isGloballyMuted(at: now) || cameraMuteEnd(entry: entry, at: now) != nil
    }

    /// Active per-camera mutes, the one ending first first.
    public func activeCameraMutes(at now: Date) -> [CameraMute] {
        cameras
            .filter { $0.value > now }
            .map { CameraMute(entry: $0.key, until: $0.value) }
            .sorted { ($0.until, $0.entry) < ($1.until, $1.entry) }
    }

    /// The next moment a mute ends (refreshes the menu bar icon and menu).
    public func nextExpiry(after now: Date) -> Date? {
        (Array(cameras.values) + [globalUntil].compactMap { $0 })
            .filter { $0 > now }
            .min()
    }

    public mutating func muteAll(for seconds: TimeInterval, from now: Date) {
        globalUntil = now.addingTimeInterval(seconds)
    }

    /// Replaces an existing mute of that camera (the user picked a new length).
    public mutating func mute(entry: String, for seconds: TimeInterval, from now: Date) {
        cameras[entry] = now.addingTimeInterval(seconds)
    }

    public mutating func clearGlobal() {
        globalUntil = nil
    }

    public mutating func clear(entry: String) {
        cameras[entry] = nil
    }

    public mutating func clearAll() {
        globalUntil = nil
        cameras = [:]
    }

    /// Drops ended mutes and, when `validEntries` is given, mutes of removed cameras.
    public mutating func prune(at now: Date, validEntries: Set<String>? = nil) {
        if let globalUntil, globalUntil <= now {
            self.globalUntil = nil
        }
        cameras = cameras.filter { entry, end in
            end > now && (validEntries?.contains(entry) ?? true)
        }
    }
}
