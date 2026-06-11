import AppKit

final class PopupWindow: NSPanel {
    private static let cornerRadius: CGFloat = 12

    private let thumbnailView = NSImageView()
    private let playerView = VLCPlayerContainerView()
    private let clickCatcher = ClickCatchingView()
    private let muteBar = MuteBarView()
    private var autoCloseTimer: Timer?
    private var escapeMonitor: Any?
    private var autoCloseSeconds: Double = 0
    private var autoCloseDeadline: Date?
    private var mouseInside = false
    private let streamURL: String
    private let soundEnabled: Bool
    private let onClose: () -> Void

    init(
        frame: NSRect,
        streamURL: String,
        soundEnabled: Bool = true,
        thumbnailDataURI: String?,
        autoCloseSeconds: Double,
        onClose: @escaping () -> Void
    ) {
        self.onClose = onClose
        self.streamURL = streamURL
        self.soundEnabled = soundEnabled

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
        playerView.play(urlString: streamURL, soundEnabled: soundEnabled) { [weak self] in
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
        // A left-click only dismisses the popup when the video is not zoomed in.
        // While zoomed, a click is reserved for panning, so it must not close.
        clickCatcher.onClick = { [weak self] in
            guard let self else { return }
            if !self.playerView.isZoomedIn {
                self.closePopup()
            }
        }
        // A right-click always closes, regardless of zoom state.
        clickCatcher.onRightClick = { [weak self] in
            self?.closePopup()
        }
        clickCatcher.onScroll = { [weak self] delta, location in
            self?.playerView.zoom(by: delta * 0.01, at: location)
        }
        clickCatcher.onMagnify = { [weak self] magnification, location in
            self?.playerView.zoom(by: magnification, at: location)
        }
        clickCatcher.onDrag = { [weak self] delta in
            self?.playerView.pan(by: delta)
        }
        clickCatcher.isZoomedIn = { [weak self] in
            self?.playerView.isZoomedIn ?? false
        }
        clickCatcher.onMouseEnter = { [weak self] in
            self?.pauseAutoClose()
            self?.muteBar.setHovering(true)
        }
        clickCatcher.onMouseExit = { [weak self] in
            self?.resumeAutoClose()
            self?.muteBar.setHovering(false)
        }

        muteBar.translatesAutoresizingMaskIntoConstraints = false
        muteBar.onMute = { [weak self] duration in
            SettingsStore.shared.mute(for: duration)
            self?.closePopup()
        }

        content.addSubview(thumbnailView)
        content.addSubview(playerView)
        content.addSubview(clickCatcher)
        content.addSubview(muteBar)

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

            muteBar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -8),
            muteBar.topAnchor.constraint(equalTo: content.topAnchor, constant: 8),
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
    /// Fired on a left-click that was not a drag.
    var onClick: (() -> Void)?
    var onRightClick: (() -> Void)?
    var onMouseEnter: (() -> Void)?
    var onMouseExit: (() -> Void)?
    /// Scroll-wheel zoom: (verticalDelta, locationInView).
    var onScroll: ((CGFloat, NSPoint) -> Void)?
    /// Trackpad pinch zoom: (magnification, locationInView).
    var onMagnify: ((CGFloat, NSPoint) -> Void)?
    /// Click-and-drag pan delta (in view coordinates) since the last event.
    var onDrag: ((CGSize) -> Void)?
    var isZoomedIn: (() -> Bool)?

    private var mouseDownLocation: NSPoint?
    private var lastDragLocation: NSPoint?
    private var didDrag = false
    private static let dragThreshold: CGFloat = 3

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
        let location = convert(event.locationInWindow, from: nil)
        mouseDownLocation = location
        lastDragLocation = location
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        guard let last = lastDragLocation, let start = mouseDownLocation else { return }

        if abs(location.x - start.x) > Self.dragThreshold || abs(location.y - start.y) > Self.dragThreshold {
            didDrag = true
        }

        if didDrag {
            onDrag?(CGSize(width: location.x - last.x, height: location.y - last.y))
            lastDragLocation = location
        }
    }

    override func mouseUp(with event: NSEvent) {
        if !didDrag {
            onClick?()
        }
        mouseDownLocation = nil
        lastDragLocation = nil
        didDrag = false
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?()
    }

    override func scrollWheel(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        onScroll?(event.scrollingDeltaY, location)
    }

    override func magnify(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        onMagnify?(event.magnification, location)
    }

    override func resetCursorRects() {
        if isZoomedIn?() == true {
            addCursorRect(bounds, cursor: .openHand)
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

/// Two stacked icon buttons (top-right of the popup) that mute all popups for a
/// fixed duration. Visible always, but emphasised while the mouse hovers.
private final class MuteBarView: NSView {
    /// Called with the mute duration in seconds.
    var onMute: ((TimeInterval) -> Void)?

    private let stack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        let oneHour = makeButton(title: "1h", duration: 60 * 60)
        oneHour.toolTip = "Alle Popups für 1 Stunde stummschalten"
        let fifteen = makeButton(title: "15m", duration: 15 * 60)
        fifteen.toolTip = "Alle Popups für 15 Minuten stummschalten"

        stack.orientation = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(oneHour)
        stack.addArrangedSubview(fifteen)
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        alphaValue = 0.55
    }

    private func makeButton(title: String, duration: TimeInterval) -> NSButton {
        let button = FirstMouseButton()
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        button.layer?.cornerRadius = 6
        button.contentTintColor = .white
        button.image = NSImage(
            systemSymbolName: "bell.slash.fill",
            accessibilityDescription: "Stummschalten"
        )
        button.imagePosition = .imageLeading
        button.imageScaling = .scaleProportionallyDown
        button.title = title
        button.font = .systemFont(ofSize: 11, weight: .semibold)
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            ]
        )
        button.target = self
        button.action = #selector(muteTapped(_:))
        button.tag = Int(duration)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return button
    }

    @objc private func muteTapped(_ sender: NSButton) {
        onMute?(TimeInterval(sender.tag))
    }

    func setHovering(_ hovering: Bool) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            animator().alphaValue = hovering ? 1.0 : 0.55
        }
    }
}

/// An `NSButton` that fires on the first click even when its window is not key,
/// which is required inside the non-activating popup panel.
private final class FirstMouseButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
