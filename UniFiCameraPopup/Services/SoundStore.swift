import AppCore
import AVFoundation
import Combine
import Foundation

/// Einstellungen › Ton: announcements, microphone, talk mode, the two volumes.
/// Own UserDefaults key and files in Application Support – not part of the configuration export.
@MainActor
final class SoundStore: ObservableObject {
    static let shared = SoundStore()

    @Published var settings: SoundSettings {
        didSet { save() }
    }

    /// ~/Library/Application Support/UniFi Camera Popup/Sounds
    let folder: URL
    private static let storageKey = "unifi.camera.popup.sound"
    /// Set once the built-in "Gong" was offered, so a deleted Gong does not come back.
    private static let gongSeededKey = "unifi.camera.popup.sound.gongSeeded"
    private static let systemGong = URL(fileURLWithPath: "/System/Library/Sounds/Glass.aiff")
    #if DEBUG
    // `--render-snapshots`: throwaway defaults suite and a temporary folder, nothing reaches the real ones.
    private let defaults = SnapshotRenderer.isActive ? SnapshotRenderer.isolatedDefaults : UserDefaults.standard
    private static let isSnapshot = SnapshotRenderer.isActive
    #else
    private let defaults = UserDefaults.standard
    private static let isSnapshot = false
    #endif

    /// Saved settings could not be decoded: no cleanup, and the old blob is backed up before the first save.
    private var loadFailed = false

    private init() {
        if Self.isSnapshot {
            folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("UniFiCameraPopup-snapshot-sounds", isDirectory: true)
        } else {
            folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("UniFi Camera Popup/Sounds", isDirectory: true)
        }
        let stored = defaults.data(forKey: Self.storageKey)
        if let stored, let saved = try? JSONDecoder().decode(SoundSettings.self, from: stored) {
            settings = saved
        } else {
            settings = SoundSettings()
            // A blob exists but is unreadable (corrupt, newer schema): keep files and blob untouched.
            loadFailed = stored != nil
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard !loadFailed, defaults.data(forKey: Self.storageKey + ".corrupt-backup") == nil else { return }
        removeUnreferencedFiles()
        if !Self.isSnapshot {
            seedGongIfNeeded()
            measureMissingLoudness()
        }
    }

    // MARK: Loudness

    /// Measures the common-loudness factor of `buffer`, stores it on the entry and returns it.
    @discardableResult
    func storeLoudness(of buffer: AVAudioPCMBuffer, for id: UUID) -> Float {
        let gain = (try? AnnouncementAudio.loudnessGain(of: buffer)) ?? 1
        if var entry = settings.announcement(id: id), entry.loudnessGain == nil {
            entry.loudnessGain = Double(gain)
            settings.update(entry)
        }
        return gain
    }

    /// Entries from before Phase 5 (and the bundled recordings): measured once in the background.
    private func measureMissingLoudness() {
        let pending = settings.announcements.compactMap { entry -> (UUID, URL)? in
            guard entry.loudnessGain == nil, let url = audioURL(for: entry) else { return nil }
            return (entry.id, url)
        }
        guard !pending.isEmpty else { return }
        Task.detached(priority: .utility) {
            for (id, url) in pending {
                guard let buffer = try? AnnouncementAudio.load(url),
                      let gain = try? AnnouncementAudio.loudnessGain(of: buffer) else { continue }
                await MainActor.run {
                    guard var entry = SoundStore.shared.settings.announcement(id: id), entry.loudnessGain == nil else { return }
                    entry.loudnessGain = Double(gain)
                    SoundStore.shared.settings.update(entry)
                }
            }
        }
    }

    // MARK: Audio

    /// Playable audio of an entry: copied/rendered file, else the bundled MP3. nil = file missing.
    func audioURL(for announcement: Announcement) -> URL? {
        if let name = announcement.fileName {
            guard let url = resolve(name) else { return nil }
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        if let resource = announcement.bundledResource {
            return Bundle.main.url(forResource: resource, withExtension: "mp3")
        }
        return nil
    }

    /// Audio for "Anhören": the text as „Übernehmen“ would render it (Anna).
    func previewBuffer(text: String) async throws -> AVAudioPCMBuffer {
        try await AnnouncementAudio.render(text: text, voiceIdentifier: AnnouncementAudio.preferredVoice()?.identifier)
    }

    /// Maps a stored file name to a URL inside the sound folder: only the last path component
    /// counts, and the result must lie in the folder. nil = unusable name.
    private func resolve(_ name: String) -> URL? {
        let component = (name as NSString).lastPathComponent
        guard !component.isEmpty, component != ".", component != ".." else { return nil }
        let base = folder.standardizedFileURL
        let url = base.appendingPathComponent(component).standardizedFileURL
        let prefix = base.path.hasSuffix("/") ? base.path : base.path + "/"
        return url.path.hasPrefix(prefix) && url.path != base.path ? url : nil
    }

    /// First run: the built-in "Gong" is a copy of the macOS system sound (never bundled).
    private func seedGongIfNeeded() {
        guard !defaults.bool(forKey: Self.gongSeededKey) else { return }
        defaults.set(true, forKey: Self.gongSeededKey)
        guard !settings.announcements.contains(where: { $0.name == "Gong" }),
              FileManager.default.fileExists(atPath: Self.systemGong.path),
              let duration = try? AnnouncementAudio.duration(of: Self.systemGong), duration > 0,
              duration <= SoundSettings.maxFileDuration else { return }
        let name = "\(UUID().uuidString).aiff"
        guard let target = resolve(name),
              (try? FileManager.default.copyItem(at: Self.systemGong, to: target)) != nil else { return }
        let level = (try? AnnouncementAudio.load(target)).flatMap { try? AnnouncementAudio.loudnessGain(of: $0) }
        settings.add(Announcement(name: "Gong", kind: .file, fileName: name, duration: duration, loudnessGain: level.map(Double.init)))
        save()
    }

    // MARK: Editing

    /// "MP3 hinzufügen …": copies the file into the sound folder and appends an entry.
    @discardableResult
    func addFile(from source: URL) throws -> Announcement {
        let entry = try importFile(source, into: Announcement(name: Announcement.suggestedName(forFile: source), kind: .file))
        settings.add(entry)
        TalkbackLog.write("Ansage hinzugefügt: \(entry.name) (\(Announcement.lengthText(entry.duration)))")
        return entry
    }

    /// "Ansage aus Text …": new empty text entry for Anna (else the best German voice).
    @discardableResult
    func addText() -> Announcement {
        let entry = Announcement(
            name: Announcement.newName,
            kind: .speech,
            voiceIdentifier: AnnouncementAudio.preferredVoice()?.identifier
        )
        settings.add(entry)
        return entry
    }

    /// Editor segment "MP3-Datei" › "Datei wählen …": the entry now plays this file.
    func replaceWithFile(id: UUID, from source: URL) throws {
        guard let current = settings.announcement(id: id) else { return }
        var entry = try importFile(source, into: current)
        if current.hasAutomaticName || current.kind == .speech {
            entry.name = Announcement.suggestedName(forFile: source)
        }
        entry.kind = .file
        entry.text = ""
        entry.voiceIdentifier = nil
        entry.bundledResource = nil
        settings.update(entry)
        deleteFile(current.fileName)
    }

    /// "Übernehmen": the text becomes the entry's audio, always spoken by Anna (Phase 5; entries in
    /// another voice – the bundled recordings too – change to Anna on their next rendering).
    func applySpeech(id: UUID, text: String) async throws {
        guard let current = settings.announcement(id: id) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var entry = current
        entry.kind = .speech
        entry.text = trimmed
        let voice = AnnouncementAudio.preferredVoice()?.identifier
        let buffer = try await AnnouncementAudio.render(text: trimmed, voiceIdentifier: voice)
        let name = "\(UUID().uuidString).caf"
        guard let target = resolve(name) else { throw TalkbackError.audioFile("Ablage") }
        try AnnouncementAudio.write(buffer, to: target)
        entry.voiceIdentifier = voice
        entry.fileName = name
        entry.duration = Double(buffer.frameLength) / buffer.format.sampleRate
        entry.loudnessGain = (try? AnnouncementAudio.loudnessGain(of: buffer)).map(Double.init)
        // Deleted while rendering: drop the new file.
        guard var latest = settings.announcement(id: id) else {
            deleteFile(entry.fileName)
            return
        }
        // Edited while rendering (e.g. renamed): apply only the rendered fields to the current state.
        let previousFile = latest.fileName
        latest.kind = entry.kind
        latest.text = entry.text
        latest.voiceIdentifier = entry.voiceIdentifier
        latest.fileName = entry.fileName
        latest.duration = entry.duration
        latest.loudnessGain = entry.loudnessGain
        if latest.hasAutomaticName {
            latest.name = Announcement.suggestedName(forText: trimmed)
        }
        settings.update(latest)
        if previousFile != latest.fileName {
            deleteFile(previousFile)
        }
    }

    func rename(id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var entry = settings.announcement(id: id) else { return }
        entry.name = String(trimmed.prefix(60))
        settings.update(entry)
    }

    func remove(id: UUID) {
        let removed = settings.remove(id: id)
        deleteFile(removed?.fileName)
    }

    // MARK: Files

    private func importFile(_ source: URL, into entry: Announcement) throws -> Announcement {
        let duration = try AnnouncementAudio.duration(of: source)
        guard duration.isFinite, duration > 0 else { throw TalkbackError.audioFile("leer") }
        guard duration <= SoundSettings.maxFileDuration else { throw TalkbackError.fileTooLong }
        let ext = source.pathExtension.isEmpty ? "mp3" : source.pathExtension.lowercased()
        let name = "\(UUID().uuidString).\(ext)"
        guard let target = resolve(name) else { throw TalkbackError.audioFile("Ablage") }
        do {
            try FileManager.default.copyItem(at: source, to: target)
        } catch {
            throw TalkbackError.audioFile(error.localizedDescription)
        }
        var updated = entry
        updated.fileName = name
        updated.duration = duration
        // Measured once here (a 5-minute MP3 decodes in well under a second).
        updated.loudnessGain = (try? AnnouncementAudio.load(target))
            .flatMap { try? AnnouncementAudio.loudnessGain(of: $0) }
            .map(Double.init)
        return updated
    }

    private func deleteFile(_ name: String?) {
        guard let name, let url = resolve(name) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Leftovers of deleted or re-rendered entries (e.g. after a crash).
    private func removeUnreferencedFiles() {
        let keep = settings.referencedFiles
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for file in files where !keep.contains(file) {
            deleteFile(file)
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        if loadFailed {
            loadFailed = false
            let backupKey = Self.storageKey + ".corrupt-backup"
            if defaults.data(forKey: backupKey) == nil, let old = defaults.data(forKey: Self.storageKey) {
                defaults.set(old, forKey: backupKey)
            }
        }
        defaults.set(data, forKey: Self.storageKey)
    }
}
