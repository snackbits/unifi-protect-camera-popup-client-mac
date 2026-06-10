import AppKit

final class PopupWindow: NSPanel {
    private static let cornerRadius: CGFloat = 12

    private let thumbnailView = NSImageView()
    private let playerView = VLCPlayerContainerView()
    private let clickCatcher = ClickCatchingView()
    private var autoCloseTimer: Timer?
    private var escapeMonitor: Any?
    private var autoCloseSeconds: Double = 0
    private var autoCloseDeadline: Date?
    private var mouseInside = false
    private let streamURL: String
    private let onClose: () -> Void

    init(
        frame: NSRect,
        streamURL: String,
        thumbnailDataURI: String?,
        autoCloseSeconds: Double,
        onClose: @escaping () -> Void
    ) {
        self.onClose = onClose
        self.streamURL = streamURL

        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true

        setupContent(thumbnailDataURI: thumbnailDataURI)
        setupCloseHandlers(autoCloseSeconds: autoCloseSeconds)
    }

    // Never become the key/main window so keyboard focus stays in the app the
    // user is currently working in. Mouse clicks and hover tracking still work.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func startPlayback() {
        playerView.play(urlString: streamURL) { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                self.playerView.animator().alphaValue = 1
                self.thumbnailView.animator().alphaValue = 0
            }
        }
    }

    private func setupContent(thumbnailDataURI: String?) {
        guard let content = contentView else { return }

        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.black.cgColor
        content.layer?.cornerRadius = Self.cornerRadius
        content.layer?.masksToBounds = true

        thumbnailView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailView.wantsLayer = true
        thumbnailView.layer?.cornerRadius = Self.cornerRadius
        thumbnailView.layer?.masksToBounds = true
        thumbnailView.alphaValue = 1

        playerView.translatesAutoresizingMaskIntoConstraints = false
        playerView.wantsLayer = true
        playerView.layer?.cornerRadius = Self.cornerRadius
        playerView.layer?.masksToBounds = true
        playerView.alphaValue = 0

        clickCatcher.translatesAutoresizingMaskIntoConstraints = false
        clickCatcher.onClick = { [weak self] in
            self?.closePopup()
        }
        clickCatcher.onMouseEnter = { [weak self] in
            self?.pauseAutoClose()
        }
        clickCatcher.onMouseExit = { [weak self] in
            self?.resumeAutoClose()
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
    }

    private func setupCloseHandlers(autoCloseSeconds: Double) {
        self.autoCloseSeconds = autoCloseSeconds

        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.closePopup()
                return nil
            }
            return event
        }

        scheduleAutoClose(after: autoCloseSeconds)
    }

    private func scheduleAutoClose(after seconds: TimeInterval) {
        autoCloseTimer?.invalidate()
        autoCloseTimer = nil
        autoCloseDeadline = seconds > 0 ? Date().addingTimeInterval(seconds) : nil
        guard seconds > 0, !mouseInside else { return }

        autoCloseTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            self?.closePopup()
        }
    }

    private func pauseAutoClose() {
        mouseInside = true
        guard autoCloseTimer != nil else { return }

        autoCloseTimer?.invalidate()
        autoCloseTimer = nil
    }

    private func resumeAutoClose() {
        mouseInside = false
        guard let deadline = autoCloseDeadline else { return }

        let remaining = deadline.timeIntervalSinceNow
        guard remaining > 0 else {
            closePopup()
            return
        }

        autoCloseTimer = Timer.scheduledTimer(withTimeInterval: remaining, repeats: false) { [weak self] _ in
            self?.closePopup()
        }
    }

    func extendAutoClose(seconds: Double) {
        autoCloseSeconds = seconds
        scheduleAutoClose(after: seconds)
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
    var onMouseEnter: (() -> Void)?
    var onMouseExit: (() -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEnter?()
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExit?()
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
