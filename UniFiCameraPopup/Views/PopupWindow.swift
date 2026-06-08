import AppKit

final class PopupWindow: NSPanel {
    private let thumbnailView = NSImageView()
    private let playerView = VLCPlayerContainerView()
    private let clickCatcher = ClickCatchingView()
    private var autoCloseTimer: Timer?
    private var escapeMonitor: Any?
    private let onClose: () -> Void

    init(
        frame: NSRect,
        streamURL: String,
        thumbnailDataURI: String?,
        autoCloseSeconds: Double,
        onClose: @escaping () -> Void
    ) {
        self.onClose = onClose

        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .black
        isOpaque = true
        hasShadow = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true

        setupContent(streamURL: streamURL, thumbnailDataURI: thumbnailDataURI)
        setupCloseHandlers(autoCloseSeconds: autoCloseSeconds)
    }

    private func setupContent(streamURL: String, thumbnailDataURI: String?) {
        guard let content = contentView else { return }

        thumbnailView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailView.wantsLayer = true
        thumbnailView.alphaValue = 1

        playerView.translatesAutoresizingMaskIntoConstraints = false
        playerView.alphaValue = 0

        clickCatcher.translatesAutoresizingMaskIntoConstraints = false
        clickCatcher.onClick = { [weak self] in
            self?.closePopup()
        }

        content.addSubview(thumbnailView)
        content.addSubview(playerView)
        content.addSubview(clickCatcher)

        NSLayoutConstraint.activate([
            thumbnailView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            thumbnailView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            thumbnailView.topAnchor.constraint(equalTo: content.topAnchor),
            thumbnailView.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            playerView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            playerView.topAnchor.constraint(equalTo: content.topAnchor),
            playerView.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            clickCatcher.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            clickCatcher.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            clickCatcher.topAnchor.constraint(equalTo: content.topAnchor),
            clickCatcher.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        if let thumbnailDataURI, let image = imageFromDataURI(thumbnailDataURI) {
            thumbnailView.image = image
        }

        playerView.play(urlString: streamURL) { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                self.playerView.animator().alphaValue = 1
                self.thumbnailView.animator().alphaValue = 0
            }
        }
    }

    private func setupCloseHandlers(autoCloseSeconds: Double) {
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.closePopup()
                return nil
            }
            return event
        }

        if autoCloseSeconds > 0 {
            autoCloseTimer = Timer.scheduledTimer(withTimeInterval: autoCloseSeconds, repeats: false) { [weak self] _ in
                self?.closePopup()
            }
        }
    }

    func extendAutoClose(seconds: Double) {
        autoCloseTimer?.invalidate()
        guard seconds > 0 else { return }
        autoCloseTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            self?.closePopup()
        }
    }

    func closePopup() {
        autoCloseTimer?.invalidate()
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
        playerView.stop()
        orderOut(nil)
        onClose()
    }

    private func imageFromDataURI(_ dataURI: String) -> NSImage? {
        let parts = dataURI.split(separator: ",", maxSplits: 1)
        guard parts.count == 2 else { return nil }

        let base64 = String(parts[1])
        guard let data = Data(base64Encoded: base64) else { return nil }
        return NSImage(data: data)
    }
}

private final class ClickCatchingView: NSView {
    var onClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
