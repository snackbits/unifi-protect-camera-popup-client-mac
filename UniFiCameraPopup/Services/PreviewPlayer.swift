import AppCore
import AVFoundation

/// "Probehören" / "Anhören" on this Mac's speakers (never sent to a camera).
@MainActor
final class PreviewPlayer: ObservableObject {
    static let shared = PreviewPlayer()

    /// Announcement being previewed; nil when silent.
    @Published private(set) var playingId: UUID?
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private var connectedFormat: AVAudioFormat?
    private var generation = 0

    private init() {
        engine.attach(node)
    }

    func play(_ buffer: AVAudioPCMBuffer, id: UUID) {
        stop()
        do {
            let playable = try AnnouncementAudio.standardized(buffer)
            if connectedFormat != playable.format {
                engine.disconnectNodeOutput(node)
                engine.connect(node, to: engine.mainMixerNode, format: playable.format)
                connectedFormat = playable.format
            }
            if !engine.isRunning { try engine.start() }
            generation += 1
            let current = generation
            playingId = id
            // Called on the render thread.
            node.scheduleBuffer(playable, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.generation == current else { return }
                    self.playingId = nil
                    self.engine.pause()
                }
            }
            node.play()
        } catch {
            NSLog("Preview failed: \(error.localizedDescription)")
            playingId = nil
        }
    }

    func stop() {
        generation += 1
        node.stop()
        if engine.isRunning { engine.pause() }
        playingId = nil
    }
}
