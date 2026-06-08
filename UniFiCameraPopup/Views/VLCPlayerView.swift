import AppKit
import VLCKitSPM

final class VLCPlayerContainerView: NSView, VLCMediaPlayerDelegate {
    private let videoView = VLCVideoView()
    private lazy var player: VLCMediaPlayer = {
        let player = VLCMediaPlayer(videoView: videoView)
        player.delegate = self
        return player
    }()

    private var onFirstFrame: (() -> Void)?
    private var hasNotifiedFirstFrame = false
    private var pendingURL: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        videoView.fillScreen = true
        videoView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(videoView)

        NSLayoutConstraint.activate([
            videoView.leadingAnchor.constraint(equalTo: leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: trailingAnchor),
            videoView.topAnchor.constraint(equalTo: topAnchor),
            videoView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        guard window != nil, let pendingURL else { return }
        self.pendingURL = nil
        beginPlayback(urlString: pendingURL)
    }

    func play(urlString: String, onFirstFrame: @escaping () -> Void) {
        self.onFirstFrame = onFirstFrame
        hasNotifiedFirstFrame = false
        pendingURL = urlString

        if window != nil {
            pendingURL = nil
            beginPlayback(urlString: urlString)
        }
    }

    private func beginPlayback(urlString: String) {
        guard let url = URL(string: urlString) else {
            NSLog("VLC: invalid stream URL")
            return
        }

        _ = player

        let media = VLCMedia(url: url)
        media.addOption(":network-caching=300")
        media.addOption(":rtsp-tcp")
        media.addOption(":avcodec-hw=none")

        player.stop()
        player.media = media
        player.audio?.isMuted = false
        player.play()

        NSLog("VLC: starting playback for \(url.host ?? "unknown")")
    }

    func stop() {
        pendingURL = nil
        player.stop()
        player.media = nil
        onFirstFrame = nil
        hasNotifiedFirstFrame = false
    }

    func mediaPlayerStateChanged(_ aNotification: Notification!) {
        guard let player = aNotification.object as? VLCMediaPlayer else { return }

        let stateName = VLCMediaPlayerStateToString(player.state) ?? "unknown"
        NSLog("VLC state: \(stateName)")

        switch player.state {
        case .playing, .buffering:
            notifyFirstFrameIfNeeded()
        case .error:
            NSLog("VLC playback error for stream")
        default:
            break
        }
    }

    func mediaPlayerTimeChanged(_ aNotification: Notification!) {
        guard let player = aNotification.object as? VLCMediaPlayer else { return }
        if player.time.intValue > 0 {
            notifyFirstFrameIfNeeded()
        }
    }

    private func notifyFirstFrameIfNeeded() {
        guard !hasNotifiedFirstFrame else { return }
        hasNotifiedFirstFrame = true
        DispatchQueue.main.async { [weak self] in
            self?.onFirstFrame?()
        }
    }
}
