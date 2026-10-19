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
    /// Watches VLC's displayed-picture counter: audio and an empty video output come seconds before
    /// the first key frame, so neither may reveal the (still black) player.
    private var firstFrameTimer: Timer?
    private var pendingURL: String?
    /// URL as handed in (direct console address); mapped per playback start, so a
    /// route change or a tunnel reset can replay the same stream on the new path.
    private var originalURL: String?
    private var routeObservers: [NSObjectProtocol] = []
    /// Bumped per playback start and by `stop()`: a late URL mapping is dropped.
    private var playbackGeneration = 0
    /// Called when the stream cannot be reached on the current route (away, not in the tunnel).
    var onUnavailable: ((String) -> Void)?

    private static let minZoom: CGFloat = 1.0
    private static let maxZoom: CGFloat = 5.0

    private(set) var zoomScale: CGFloat = 1.0
    private var panOffset: CGPoint = .zero
    private var crop: CameraCrop?

    /// When set, only the normalized crop region is shown; zoom/pan operate within it.
    var cropRegion: CameraCrop? {
        get { crop }
        set {
            crop = newValue
            needsLayout = true
            layoutSubtreeIfNeeded()
        }
    }

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
        for name in [ConnectionRouter.routeDidChangeNotification, TunnelController.connectionsResetNotification] {
            routeObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.replay() }
            })
        }
    }

    deinit {
        routeObservers.forEach(NotificationCenter.default.removeObserver)
    }

    /// Restarts the current stream (new route, or relayed connections were reset).
    private func replay() {
        guard let originalURL, window != nil else { return }
        NSLog("VLC: Stream neu verbinden")
        beginPlayback(urlString: originalURL)
    }

    override func layout() {
        super.layout()
        layoutVideoView()
    }

    private func layoutVideoView() {
        let layout = videoLayout()
        videoView.frame = layout.frame
    }

    private struct VideoLayout {
        let frame: CGRect
        let baselineOrigin: CGPoint
    }

    private func videoLayout(for scale: CGFloat? = nil, pan: CGPoint? = nil) -> VideoLayout {
        let scale = scale ?? zoomScale
        let pan = pan ?? panOffset

        if let crop, crop.width > 0, crop.height > 0 {
            let cw = CGFloat(crop.width)
            let ch = CGFloat(crop.height)
            let cx = CGFloat(crop.x)
            let cy = CGFloat(crop.y)

            let scaledWidth = bounds.width / cw * scale
            let scaledHeight = bounds.height / ch * scale
            let baselineOrigin = CGPoint(x: -cx * scaledWidth, y: -cy * scaledHeight)
            let origin = CGPoint(x: baselineOrigin.x + pan.x, y: baselineOrigin.y + pan.y)
            return VideoLayout(
                frame: CGRect(x: origin.x, y: origin.y, width: scaledWidth, height: scaledHeight),
                baselineOrigin: baselineOrigin
            )
        }

        let scaledWidth = bounds.width * scale
        let scaledHeight = bounds.height * scale
        let baselineOrigin = CGPoint(
            x: (bounds.width - scaledWidth) / 2,
            y: (bounds.height - scaledHeight) / 2
        )
        let origin = CGPoint(x: baselineOrigin.x + pan.x, y: baselineOrigin.y + pan.y)
        return VideoLayout(
            frame: CGRect(x: origin.x, y: origin.y, width: scaledWidth, height: scaledHeight),
            baselineOrigin: baselineOrigin
        )
    }

    /// Zooms toward `point` (in this view's coordinate space) by a multiplicative
    /// `factor` (e.g. 0.1 zooms in 10%, -0.1 zooms out 10%).
    func zoom(by factor: CGFloat, at point: NSPoint) {
        setZoom(scale: zoomScale * (1 + factor), at: point)
    }

    private func setZoom(scale rawScale: CGFloat, at point: NSPoint) {
        let newScale = min(max(rawScale, Self.minZoom), Self.maxZoom)
        let oldLayout = videoLayout()

        // Keep the content under the cursor anchored while zooming.
        let unit = CGPoint(
            x: oldLayout.frame.width > 0 ? (point.x - oldLayout.frame.minX) / oldLayout.frame.width : 0.5,
            y: oldLayout.frame.height > 0 ? (point.y - oldLayout.frame.minY) / oldLayout.frame.height : 0.5
        )

        let newLayout = videoLayout(for: newScale, pan: .zero)
        let newSize = newLayout.frame.size
        let newOrigin = CGPoint(
            x: point.x - unit.x * newSize.width,
            y: point.y - unit.y * newSize.height
        )

        zoomScale = newScale
        panOffset = CGPoint(
            x: newOrigin.x - newLayout.baselineOrigin.x,
            y: newOrigin.y - newLayout.baselineOrigin.y
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

    func applyZoomState(scale: CGFloat, panOffset: CGPoint) {
        zoomScale = min(max(scale, Self.minZoom), Self.maxZoom)
        self.panOffset = panOffset
        clampPan()
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    var currentZoomState: (scale: CGFloat, panOffset: CGPoint) {
        (zoomScale, panOffset)
    }

    private func clampPan() {
        if crop != nil {
            // Pan range keeps the crop region filling the view while zoomed in.
            let minX = bounds.width * (1 - zoomScale)
            let minY = bounds.height * (1 - zoomScale)
            panOffset.x = min(max(panOffset.x, minX), 0)
            panOffset.y = min(max(panOffset.y, minY), 0)
        } else {
            let maxX = max(0, (bounds.width * zoomScale - bounds.width) / 2)
            let maxY = max(0, (bounds.height * zoomScale - bounds.height) / 2)
            panOffset.x = min(max(panOffset.x, -maxX), maxX)
            panOffset.y = min(max(panOffset.y, -maxY), maxY)
        }
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
        originalURL = urlString
        pendingURL = urlString
        self.soundEnabled = soundEnabled

        if window != nil {
            pendingURL = nil
            beginPlayback(urlString: urlString)
        }
    }

    private var soundEnabled = true

    /// Maps the URL onto the current route first. Away and not reachable through the tunnel:
    /// no fallback to the direct address – `onUnavailable` reports it instead.
    private func beginPlayback(urlString: String) {
        playbackGeneration += 1
        let attempt = playbackGeneration
        Task { @MainActor [weak self] in
            let mapped = await ConnectionRouter.shared.playableStreamURL(urlString)
            guard let self, attempt == self.playbackGeneration else { return }
            guard let mapped else {
                self.player.stop()
                self.onUnavailable?(TunnelRouteError.streamUnreachable.errorDescription ?? "")
                return
            }
            self.startMedia(urlString: mapped)
        }
    }

    private func startMedia(urlString: String) {
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
        watchForFirstPicture(of: media)

        NSLog("VLC: starting playback for \(url.host ?? "unknown")")
    }

    private func watchForFirstPicture(of media: VLCMedia) {
        firstFrameTimer?.invalidate()
        guard !hasNotifiedFirstFrame else { return }
        let started = Date()
        // `player.media` hands out a new wrapper object per call – never compare it by identity;
        // the playback generation tells whether this media is still the one playing.
        let generation = playbackGeneration
        firstFrameTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, generation == self.playbackGeneration, !self.hasNotifiedFirstFrame else {
                    timer.invalidate()
                    return
                }
                // A stream that never reports pictures still gets shown after 10 s.
                if media.statistics.displayedPictures > 0 || Date().timeIntervalSince(started) > 10 {
                    timer.invalidate()
                    self.notifyFirstFrameIfNeeded()
                }
            }
        }
    }

    func stop() {
        firstFrameTimer?.invalidate()
        firstFrameTimer = nil
        pendingURL = nil
        originalURL = nil
        playbackGeneration += 1
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

        // The first picture is detected by `watchForFirstPicture` – `.playing`, `.buffering`,
        // `hasVideoOut` and a running clock all come before it (black popup with sound only).
        switch player.state {
        case .error:
            NSLog("VLC playback error for stream")
        default:
            break
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
