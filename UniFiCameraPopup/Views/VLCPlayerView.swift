import AppKit
import VLCKitSPM

final class VLCPlayerContainerView: NSView, VLCMediaPlayerDelegate {
    private let videoView = VLCVideoView()
    private let player = VLCMediaPlayer()
    private var onFirstFrame: (() -> Void)?
    private var hasNotifiedFirstFrame = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        videoView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(videoView)

        NSLayoutConstraint.activate([
            videoView.leadingAnchor.constraint(equalTo: leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: trailingAnchor),
            videoView.topAnchor.constraint(equalTo: topAnchor),
            videoView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        player.drawable = videoView
        player.delegate = self
    }

    func play(urlString: String, onFirstFrame: @escaping () -> Void) {
        self.onFirstFrame = onFirstFrame
        hasNotifiedFirstFrame = false

        guard let url = URL(string: urlString) else { return }

        let media = VLCMedia(url: url)
        media.addOption(":network-caching=300")
        media.addOption(":rtsp-tcp")

        player.media = media
        player.audio?.isMuted = false
        player.play()
    }

    func stop() {
        player.stop()
        player.media = nil
        onFirstFrame = nil
        hasNotifiedFirstFrame = false
    }

    func mediaPlayerStateChanged(_ aNotification: Notification!) {
        guard let player = aNotification.object as? VLCMediaPlayer else { return }

        if player.state == .playing, !hasNotifiedFirstFrame {
            hasNotifiedFirstFrame = true
            DispatchQueue.main.async { [weak self] in
                self?.onFirstFrame?()
            }
        }
    }
}
