import AppCore
import AVFoundation
import Combine
import Foundation
import ProtectKit

/// What is being sent to a camera.
enum TalkbackPurpose: Equatable {
    case talk
    case announcement(UUID)
}

/// The one talkback in progress (one microphone, one stream at a time).
struct TalkbackActivity: Equatable {
    enum Phase: Equatable {
        /// Permission, talkback session, file loading.
        case preparing
        /// Audio is flowing.
        case live
    }

    let entryId: UUID
    let purpose: TalkbackPurpose
    var phase: Phase
}

/// Error text for the popup of `entryId` (shown for a few seconds).
struct TalkbackNotice: Equatable {
    let id = UUID()
    let entryId: UUID
    let text: String
}

/// Push-to-talk and announcements: talkback session from Protect, microphone or file,
/// `TalkbackStreamer` to the camera. Every step is logged (TalkbackLog) for the hardware check.
@MainActor
final class TalkbackService: ObservableObject {
    static let shared = TalkbackService()

    @Published private(set) var activity: TalkbackActivity?
    @Published private(set) var notice: TalkbackNotice?

    private let microphone = MicrophoneCapture()
    private var current: TalkbackStreamer?
    /// Streams sending their last packets after the user stopped talking.
    private var draining: [ObjectIdentifier: TalkbackStreamer] = [:]
    /// Token of the start that may still go live; a newer start or a stop replaces it.
    private var run: UUID?
    private var spaceEntry: UUID?
    private var disarmAfterRelease = false

    private init() {}

    #if DEBUG
    /// Snapshot renderer only: shows popup states without a camera.
    func debugApply(activity: TalkbackActivity?, notice: TalkbackNotice?) {
        self.activity = activity
        self.notice = notice
    }
    #endif

    /// Sprechen and Ton abspielen exist only for Protect cameras with a speaker.
    func canTalk(_ mapping: WebhookMapping) -> Bool {
        guard SettingsStore.shared.isProtectConfigured, let cameraId = mapping.protectCameraId else { return false }
        return ProtectSession.shared.cameras.first { $0.id == cameraId }?.hasSpeaker == true
    }

    func isActive(entryId: UUID) -> Bool {
        activity?.entryId == entryId
    }

    // MARK: Push-to-talk

    /// Talk button pressed or space bar down.
    func pressTalk(entryId: UUID) {
        switch SoundStore.shared.settings.talkMode {
        case .hold:
            startTalking(entryId: entryId)
        case .toggle:
            if activity?.purpose == .talk, activity?.entryId == entryId {
                stopTalking()
            } else {
                startTalking(entryId: entryId)
            }
        }
    }

    /// Talk button or space bar released.
    func releaseTalk() {
        guard SoundStore.shared.settings.talkMode == .hold else { return }
        stopTalking()
        // Pointer left the popup while the mouse button was held: nothing else frees the space bar.
        if disarmAfterRelease { disarmSpace() }
    }

    /// VoiceOver press: always toggles.
    func toggleTalk(entryId: UUID) {
        if activity?.purpose == .talk, activity?.entryId == entryId {
            stopTalking()
        } else {
            startTalking(entryId: entryId)
        }
    }

    func startTalking(entryId: UUID) {
        if activity?.purpose == .talk { return }
        stopCurrent()
        guard let mapping = SettingsStore.shared.mapping(forEntry: entryId) else { return }
        activity = TalkbackActivity(entryId: entryId, purpose: .talk, phase: .preparing)
        let token = UUID()
        run = token
        Task { await runTalk(mapping, token: token) }
    }

    func stopTalking() {
        guard let activity, activity.purpose == .talk else { return }
        self.activity = nil
        run = nil
        // Released before the session was open: nothing is sent.
        guard activity.phase == .live else { return }
        microphone.stop()
        if let streamer = current {
            draining[ObjectIdentifier(streamer)] = streamer
            streamer.finish()
        }
        current = nil
        TalkbackLog.write("Talkback: Mikrofon zu")
    }

    private func runTalk(_ mapping: WebhookMapping, token: UUID) async {
        let entryId = mapping.entryId
        do {
            guard await MicrophoneCapture.requestPermission() else { throw TalkbackError.microphoneDenied }
            guard run == token else { return }
            let target = try await openSession(for: mapping)
            guard run == token else { return }
            let streamer = try makeStreamer(target: target, entryId: entryId)
            streamer.start()
            current = streamer
            try microphone.start(
                deviceUID: SoundStore.shared.settings.microphoneUID,
                onBuffer: Self.forward(to: streamer),
                onConfigurationChange: { [weak self] in
                    guard let self, self.run == token, self.activity?.purpose == .talk else { return }
                    TalkbackLog.write("Talkback: Mikrofon-Konfiguration geändert")
                    self.stopTalking()
                    self.notice = TalkbackNotice(entryId: entryId, text: "Mikrofon nicht mehr verfügbar.")
                }
            )
            activity?.phase = .live
            TalkbackLog.write("Talkback: Mikrofon offen für \(mapping.label)")
        } catch {
            guard run == token else { return }
            report(error, entryId: entryId)
        }
    }

    // MARK: Announcements

    func play(_ announcement: Announcement, entryId: UUID) {
        if activity?.purpose == .talk { return }
        stopCurrent()
        guard let mapping = SettingsStore.shared.mapping(forEntry: entryId) else { return }
        guard let url = SoundStore.shared.audioURL(for: announcement) else {
            report(TalkbackError.audioFile("Datei fehlt"), entryId: entryId)
            return
        }
        let purpose = TalkbackPurpose.announcement(announcement.id)
        activity = TalkbackActivity(entryId: entryId, purpose: purpose, phase: .preparing)
        let token = UUID()
        run = token
        Task { await runAnnouncement(url: url, name: announcement.name, mapping: mapping, token: token) }
    }

    func stopPlayback() {
        guard let activity, case .announcement = activity.purpose else { return }
        self.activity = nil
        run = nil
        current?.stop()
        current = nil
    }

    private func runAnnouncement(url: URL, name: String, mapping: WebhookMapping, token: UUID) async {
        let entryId = mapping.entryId
        do {
            let loading = Task.detached { () throws -> PCMBox in PCMBox(buffer: try AnnouncementAudio.load(url)) }
            let target = try await openSession(for: mapping)
            let audio = try await loading.value.buffer
            guard run == token else { return }
            let streamer = try makeStreamer(target: target, entryId: entryId)
            streamer.start()
            streamer.append(audio)
            streamer.finish()
            current = streamer
            activity?.phase = .live
            TalkbackLog.write("Talkback: Ansage „\(name)“ an \(mapping.label), \(Announcement.lengthText(Double(audio.frameLength) / audio.format.sampleRate))")
        } catch {
            guard run == token else { return }
            report(error, entryId: entryId)
        }
    }

    // MARK: Space bar (pointer over a popup that can talk)

    func pointerEntered(entryId: UUID) {
        spaceEntry = entryId
        disarmAfterRelease = false
        PushToTalkKey.shared.arm(
            onPress: { [weak self] in self?.spacePressed() },
            onRelease: { [weak self] in self?.spaceReleased() }
        )
    }

    func pointerExited(entryId: UUID) {
        guard spaceEntry == entryId else { return }
        // Still holding the space bar: keep it until released.
        if activity?.purpose == .talk, activity?.entryId == entryId, SoundStore.shared.settings.talkMode == .hold {
            disarmAfterRelease = true
            return
        }
        disarmSpace()
    }

    /// The popup closes: stop what it started, free the space bar.
    func popupClosed(entryId: UUID) {
        if activity?.entryId == entryId { stopCurrent() }
        if spaceEntry == entryId { disarmSpace() }
    }

    private func spacePressed() {
        guard let spaceEntry else { return }
        pressTalk(entryId: spaceEntry)
    }

    private func spaceReleased() {
        releaseTalk()
        if disarmAfterRelease { disarmSpace() }
    }

    private func disarmSpace() {
        PushToTalkKey.shared.disarm()
        spaceEntry = nil
        disarmAfterRelease = false
    }

    // MARK: Plumbing

    private func openSession(for mapping: WebhookMapping) async throws -> TalkbackTarget {
        guard let cameraId = mapping.protectCameraId, let client = ProtectSession.shared.client else {
            throw TalkbackError.notConnected
        }
        TalkbackLog.write("Talkback: Sitzung anfordern – \(mapping.label) (\(cameraId))")
        let session = try await client.talkbackSession(cameraId: cameraId)
        TalkbackLog.write("Talkback: Antwort \(session.raw)")
        let target = try TalkbackTarget.make(
            host: session.host,
            port: session.port,
            codecName: session.codec,
            sampleRate: session.samplingRate
        )
        TalkbackLog.write("Talkback: Ziel \(target.host):\(target.port), \(target.codec.rawValue), \(target.sampleRate) Hz, \(session.bitsPerSample) Bit")
        // Away, every session shares one UDP forward per camera, which the router frees for this
        // one. A talk still flushing its last 0.3 s would take it straight back (and keep it
        // until 3 s of silence): it is superseded, so it ends now.
        if ConnectionRouter.shared.isViaTunnel { stopDraining() }
        // Away: through a UDP forward of the tunnel (camera IP inside AllowedIPs), else a notice.
        let routed = try await ConnectionRouter.shared.talkbackTarget(target)
        if routed != target { TalkbackLog.write("Talkback: über den Tunnel (\(routed.host):\(routed.port))") }
        return routed
    }

    private func makeStreamer(target: TalkbackTarget, entryId: UUID) throws -> TalkbackStreamer {
        // Weak: the streamer owns this closure, a strong capture would keep it alive forever.
        let box = WeakStreamer()
        let made = try TalkbackStreamer(
            target: target,
            gain: SoundStore.shared.settings.gain,
            log: { TalkbackLog.write($0) },
            onEvent: { [weak self] event in
                Task { @MainActor in
                    guard let self, let streamer = box.value else { return }
                    self.handle(event, from: streamer, entryId: entryId)
                }
            }
        )
        box.value = made
        return made
    }

    private func handle(_ event: TalkbackStreamer.Event, from streamer: TalkbackStreamer, entryId: UUID) {
        switch event {
        case .ready:
            break
        case .finished:
            draining[ObjectIdentifier(streamer)] = nil
            if current === streamer {
                current = nil
                activity = nil
            }
        case .failed(let message):
            draining[ObjectIdentifier(streamer)] = nil
            guard current === streamer else { return }
            report(TalkbackError.network(message), entryId: entryId)
        }
    }

    /// Ends the talks that are still sending their closing silence, at once.
    private func stopDraining() {
        draining.values.forEach { $0.stop() }
        draining = [:]
    }

    /// Ends whatever runs now, at once.
    private func stopCurrent() {
        run = nil
        microphone.stop()
        current?.stop()
        current = nil
        activity = nil
    }

    private func report(_ error: Error, entryId: UUID) {
        let text = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        TalkbackLog.write("Talkback: Fehler – \(text)")
        if activity?.entryId == entryId {
            stopCurrent()
        }
        notice = TalkbackNotice(entryId: entryId, text: text)
    }

    private nonisolated static func forward(to streamer: TalkbackStreamer) -> @Sendable (AVAudioPCMBuffer) -> Void {
        { buffer in streamer.append(buffer) }
    }
}

/// Lets the event closure refer to its own streamer without keeping it alive.
private final class WeakStreamer: @unchecked Sendable {
    weak var value: TalkbackStreamer?
}

/// Moves a decoded file from the loading task to the main actor (read-only afterwards).
private struct PCMBox: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
}
