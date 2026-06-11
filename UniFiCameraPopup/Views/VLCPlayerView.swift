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

    private static let minZoom: CGFloat = 1.0
    private static let maxZoom: CGFloat = 5.0

    private(set) var zoomScale: CGFloat = 1.0
    private var panOffset: CGPoint = .zero

    /// True once the user has zoomed in past the resting scale.
    var isZoomedIn: Bool { zoomScale > Self.minZoom + 0.001 }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        // The video view is laid out manually (see `layout()`) so that we can
        // scale and offset it for zoom/pan. The parent clips the overflow.
        videoView.fillScreen = true
        addSubview(videoView)
    }

    override func layout() {
        super.layout()
        layoutVideoView()
    }

    private func layoutVideoView() {
        let scaledWidth = bounds.width * zoomScale
        let scaledHeight = bounds.height * zoomScale
        let originX = (bounds.width - scaledWidth) / 2 + panOffset.x
        let originY = (bounds.height - scaledHeight) / 2 + panOffset.y
        videoView.frame = CGRect(x: originX, y: originY, width: scaledWidth, height: scaledHeight)
    }

    /// Zooms toward `point` (in this view's coordinate space) by a multiplicative
    /// `factor` (e.g. 0.1 zooms in 10%, -0.1 zooms out 10%).
    func zoom(by factor: CGFloat, at point: NSPoint) {
        setZoom(scale: zoomScale * (1 + factor), at: point)
    }

    private func setZoom(scale rawScale: CGFloat, at point: NSPoint) {
        let newScale = min(max(rawScale, Self.minZoom), Self.maxZoom)
        let oldFrame = videoView.frame

        // Keep the content under the cursor anchored while zooming.
        let unit = CGPoint(
            x: oldFrame.width > 0 ? (point.x - oldFrame.minX) / oldFrame.width : 0.5,
            y: oldFrame.height > 0 ? (point.y - oldFrame.minY) / oldFrame.height : 0.5
        )
        let newSize = CGSize(width: bounds.width * newScale, height: bounds.height * newScale)
        let newOriginX = point.x - unit.x * newSize.width
        let newOriginY = point.y - unit.y * newSize.height

        zoomScale = newScale
        panOffset = CGPoint(
            x: newOriginX - (bounds.width - newSize.width) / 2,
            y: newOriginY - (bounds.height - newSize.height) / 2
        )
        clampPan()
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    /// Shifts the zoomed-in viewport by a drag delta (in this view's coordinates).
    func pan(by delta: CGSize) {
        guard isZoomedIn else { return }
        panOffset.x += delta.width
        panOffset.y += delta.height
        clampPan()
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    func resetZoom() {
        zoomScale = Self.minZoom
        panOffset = .zero
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    private func clampPan() {
        let maxX = max(0, (bounds.width * zoomScale - bounds.width) / 2)
        let maxY = max(0, (bounds.height * zoomScale - bounds.height) / 2)
        panOffset.x = min(max(panOffset.x, -maxX), maxX)
        panOffset.y = min(max(panOffset.y, -maxY), maxY)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        guard window != nil, let pendingURL else { return }
        self.pendingURL = nil
        beginPlayback(urlString: pendingURL)
    }

    func play(urlString: String, soundEnabled: Bool = true, onFirstFrame: @escaping () -> Void) {
        self.onFirstFrame = onFirstFrame
        hasNotifiedFirstFrame = false
        pendingURL = urlString
        self.soundEnabled = soundEnabled

        if window != nil {
            pendingURL = nil
            beginPlayback(urlString: urlString)
        }
    }

    private var soundEnabled = true

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
        player.audio?.isMuted = !soundEnabled
        player.play()

        NSLog("VLC: starting playback for \(url.host ?? "unknown")")
    }

    func stop() {
        pendingURL = nil
        player.stop()
        player.media = nil
        onFirstFrame = nil
        hasNotifiedFirstFrame = false
        resetZoom()
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
