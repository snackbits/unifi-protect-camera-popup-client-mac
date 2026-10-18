import AppCore
import Foundation

/// Piper voices on this Mac: the bundled Thorsten (medium) in the app, every other offered voice
/// downloaded on first use into ~/Library/Application Support/UniFi Camera Popup/Voices/<id>/
/// (pinned revision, size + SHA-256 checked), and rendering text with Piper (Process, never linked).
/// Not part of the configuration export.
@MainActor
final class PiperVoiceStore: ObservableObject {
    static let shared = PiperVoiceStore()

    /// Running downloads by voice id: bytes received so far.
    @Published private(set) var downloads: [String: Int64] = [:]
    /// Downloaded voices (not the bundled one).
    @Published private(set) var downloadedIds: Set<String> = []

    let folder: URL
    let installation = PiperInstallation(contents: Bundle.main.bundleURL.appendingPathComponent("Contents", isDirectory: true))
    private var tasks: [String: Task<PiperVoiceFiles, Error>] = [:]
    #if DEBUG
    private let isSnapshot = SnapshotRenderer.isActive
    #else
    private let isSnapshot = false
    #endif

    private init() {
        if isSnapshot {
            folder = FileManager.default.temporaryDirectory.appendingPathComponent("UniFiCameraPopup-snapshot-voices", isDirectory: true)
        } else {
            folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("UniFi Camera Popup/Voices", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        refresh()
    }

    // MARK: State

    func availability(_ voice: PiperVoice) -> VoiceAvailability {
        if voice.id == PiperVoiceCatalog.bundledVoiceId { return .bundled }
        return downloadedIds.contains(voice.id) ? .downloaded : .notDownloaded
    }

    var downloadedVoices: [PiperVoice] {
        PiperVoice.menuOrder.filter { downloadedIds.contains($0.id) }
    }

    func files(for voice: PiperVoice) -> PiperVoiceFiles {
        if voice.id == PiperVoiceCatalog.bundledVoiceId {
            return PiperVoiceFiles(voice: voice, folder: installation.bundledVoices)
        }
        return PiperVoiceFiles(voice: voice, folder: voiceFolder(voice))
    }

    private func voiceFolder(_ voice: PiperVoice) -> URL {
        folder.appendingPathComponent(voice.id, isDirectory: true)
    }

    /// A voice counts as downloaded when both files have the pinned size (the hash was checked
    /// before the folder got its final name). Leftover partial folders are removed.
    func refresh() {
        // `--render-snapshots` sets the state itself (simulateDownloaded).
        guard !isSnapshot else { return }
        var found: Set<String> = []
        for voice in PiperVoiceCatalog.offered where voice.id != PiperVoiceCatalog.bundledVoiceId {
            let files = files(for: voice)
            if Self.size(files.model) == voice.model.size, Self.size(files.config) == voice.config.size {
                found.insert(voice.id)
            }
        }
        downloadedIds = found
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for entry in entries where entry.hasSuffix(".partial") && tasks.isEmpty {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(entry))
        }
    }

    private static func size(_ url: URL) -> Int64? {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value
    }

    // MARK: Download

    /// The voice's files, downloading them first if needed (one download per voice at a time).
    func ensure(_ voice: PiperVoice) async throws -> PiperVoiceFiles {
        if availability(voice) != .notDownloaded { return files(for: voice) }
        if let running = tasks[voice.id] { return try await running.value }
        let task = Task { @MainActor [weak self] () throws -> PiperVoiceFiles in
            guard let self else { throw CancellationError() }
            return try await self.download(voice)
        }
        tasks[voice.id] = task
        defer {
            tasks[voice.id] = nil
            downloads[voice.id] = nil
        }
        return try await task.value
    }

    func cancelDownload(_ voice: PiperVoice) {
        tasks[voice.id]?.cancel()
    }

    /// Downloads into `<id>.partial/`, checks size + SHA-256 of each file against the pinned catalog,
    /// then renames the folder. Any failure or cancellation removes the partial folder. File work
    /// (moving, hashing, deleting) runs off the main thread.
    private func download(_ voice: PiperVoice) async throws -> PiperVoiceFiles {
        let partial = folder.appendingPathComponent("\(voice.id).partial", isDirectory: true)
        let final = voiceFolder(voice)
        try await Self.offMain {
            let manager = FileManager.default
            try? manager.removeItem(at: partial)
            do {
                try manager.createDirectory(at: partial, withIntermediateDirectories: true)
            } catch {
                throw PiperError.download(error.localizedDescription)
            }
        }
        downloads[voice.id] = 0
        TalkbackLog.write("Stimme: lade „\(voice.label)“ (\(voice.sizeText)) von \(voice.model.url.absoluteString)")
        do {
            var done: Int64 = 0
            for file in [voice.config, voice.model] {
                try Task.checkCancellation()
                let target = partial.appendingPathComponent(file.fileName)
                let base = done
                try await fetch(file, to: target) { [weak self] received in
                    Task { @MainActor in
                        guard let self, self.downloads[voice.id] != nil else { return }
                        self.downloads[voice.id] = base + min(received, file.size)
                    }
                }
                done += file.size
                let ok = await Task.detached(priority: .utility) { FileChecksum.matches(target, file) }.value
                guard ok else { throw PiperError.checksum(voice.label) }
            }
            try Task.checkCancellation()
            try await Self.offMain {
                let manager = FileManager.default
                try? manager.removeItem(at: final)
                try manager.moveItem(at: partial, to: final)
            }
        } catch {
            try? await Self.offMain { try? FileManager.default.removeItem(at: partial) }
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                TalkbackLog.write("Stimme: Laden von „\(voice.label)“ abgebrochen")
                throw CancellationError()
            }
            TalkbackLog.write("Stimme: Laden von „\(voice.label)“ fehlgeschlagen – \(error.localizedDescription)")
            if error is PiperError { throw error }
            throw PiperError.download((error as? URLError)?.localizedDescription ?? error.localizedDescription)
        }
        downloadedIds.insert(voice.id)
        TalkbackLog.write("Stimme: „\(voice.label)“ geladen")
        return files(for: voice)
    }

    /// One file via URLSession (only the pinned revision URL of the catalog); progress through the
    /// task's received bytes. The finished temporary file is moved off the main thread.
    private func fetch(_ file: VoiceFile, to target: URL, progress: @escaping @Sendable (Int64) -> Void) async throws {
        let observer = DownloadObserver(progress: progress)
        let (temporary, response) = try await URLSession.shared.download(from: file.url, delegate: observer)
        try await Self.offMain {
            defer { try? FileManager.default.removeItem(at: temporary) }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                throw PiperError.download("HTTP \(status)")
            }
            try FileManager.default.moveItem(at: temporary, to: target)
        }
    }

    private static func offMain<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await Task.detached(priority: .utility, operation: work).value
    }

    // MARK: Remove

    func remove(_ voice: PiperVoice) {
        guard voice.id != PiperVoiceCatalog.bundledVoiceId else { return }
        cancelDownload(voice)
        try? FileManager.default.removeItem(at: voiceFolder(voice))
        downloadedIds.remove(voice.id)
        TalkbackLog.write("Stimme: „\(voice.label)“ entfernt")
    }

    // MARK: Rendering

    /// Speaks `text` with Piper into a new WAV in the temporary folder (the caller moves or deletes it).
    /// Downloads the voice first if needed. Never falls back to another voice.
    func render(text: String, voice ref: PiperVoiceRef) async throws -> URL {
        guard let (voice, speaker) = ref.resolved else { throw PiperError.voiceNotInstalled(ref.label) }
        guard let input = PiperCommand.input(for: text) else { throw PiperError.noAudio }
        let files = try await ensure(voice)
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("piper-\(UUID().uuidString).wav")
        let arguments = PiperCommand.arguments(
            installation: installation, files: files,
            speaker: PiperCommand.speakerArgument(voice: voice, speaker: speaker), output: output
        )
        let start = Date()
        do {
            try await PiperRunner.run(executable: installation.executable, arguments: arguments, input: input)
            let data = try await Task.detached(priority: .userInitiated) { try Data(contentsOf: output) }.value
            let speech = await Task.detached(priority: .userInitiated) { WAVInfo.hasSpeech(data) }.value
            guard speech else { throw PiperError.noAudio }
        } catch {
            try? FileManager.default.removeItem(at: output)
            if !(error is CancellationError) {
                TalkbackLog.write("Piper: „\(ref.label)“ fehlgeschlagen – \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)")
            }
            throw error
        }
        TalkbackLog.write(String(format: "Piper: „%@“, %d Zeichen in %.1f s", ref.label, input.count - 1, Date().timeIntervalSince(start)))
        return output
    }

    #if DEBUG
    /// `--render-snapshots`: show a download in progress without network.
    func simulateDownload(_ voiceId: String, received: Int64?) {
        downloads[voiceId] = received
    }

    func simulateDownloaded(_ ids: Set<String>) {
        downloadedIds = ids
    }
    #endif
}

/// Reports the received bytes of the one download task it is handed.
private final class DownloadObserver: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let progress: @Sendable (Int64) -> Void
    private var observation: NSKeyValueObservation?

    init(progress: @escaping @Sendable (Int64) -> Void) {
        self.progress = progress
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        observation = task.observe(\.countOfBytesReceived, options: [.new]) { [progress] task, _ in
            progress(task.countOfBytesReceived)
        }
    }
}
