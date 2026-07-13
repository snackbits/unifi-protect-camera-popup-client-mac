import AppKit

final class PopupWindow: NSPanel {
    private static let cornerRadius: CGFloat = 12

    private let thumbnailView = NSImageView()
    private let playerView = VLCPlayerContainerView()
    private let clickCatcher = ClickCatchingView()
    private let muteBar = MuteBarView()
    private let cropSelectionView = CropSelectionView()
    private let cropActionBar = CropActionBarView()
    private var autoCloseTimer: Timer?
    private var zoomSaveTimer: Timer?
    private var escapeMonitor: Any?
    private var autoCloseSeconds: Double = 0
    private var autoCloseDeadline: Date?
    private var mouseInside = false
    private let streamURL: String
    private let soundEnabled: Bool
    private let rememberZoom: Bool
    private let initialZoom: SavedCameraZoom?
    private let cropRegion: CameraCrop?
    private let cropSelectionMode: Bool
    private let onWillClose: ((CGFloat, CGPoint) -> Void)?
    private let onCropSave: ((CameraCrop, CGSize) -> Void)?
    private let onCropCancel: (() -> Void)?
    private let onClose: () -> Void

    init(
        frame: NSRect,
        streamURL: String,
        soundEnabled: Bool = true,
        rememberZoom: Bool = false,
        initialZoom: SavedCameraZoom? = nil,
        cropRegion: CameraCrop? = nil,
        thumbnailDataURI: String?,
        autoCloseSeconds: Double,
        cropSelectionMode: Bool = false,
        onWillClose: ((CGFloat, CGPoint) -> Void)? = nil,
        onCropSave: ((CameraCrop, CGSize) -> Void)? = nil,
        onCropCancel: (() -> Void)? = nil,
        onClose: @escaping () -> Void
    ) {
        self.onClose = onClose
        self.streamURL = streamURL
        self.soundEnabled = soundEnabled
        self.rememberZoom = rememberZoom
        self.initialZoom = initialZoom
        self.cropRegion = cropRegion
        self.cropSelectionMode = cropSelectionMode
        self.onWillClose = onWillClose
        self.onCropSave = onCropSave
        self.onCropCancel = onCropCancel

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
        setupCloseHandlers(autoCloseSeconds: cropSelectionMode ? 0 : autoCloseSeconds)
    }

    // Never become the key/main window so keyboard focus stays in the app the
    // user is currently working in. Mouse clicks and hover tracking still work.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func startPlayback() {
        if let cropRegion, !cropSelectionMode {
            playerView.cropRegion = cropRegion
        }

        if let initialZoom, !cropSelectionMode {
            playerView.applyZoomState(
                scale: CGFloat(initialZoom.scale),
                panOffset: CGPoint(x: initialZoom.panOffsetX, y: initialZoom.panOffsetY)
            )
        }

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
        if cropSelectionMode {
            clickCatcher.isHidden = true
        } else {
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
                self?.scheduleZoomSave()
            }
            clickCatcher.onMagnify = { [weak self] magnification, location in
                self?.playerView.zoom(by: magnification, at: location)
                self?.scheduleZoomSave()
            }
            clickCatcher.onDrag = { [weak self] delta in
                self?.playerView.pan(by: delta)
                self?.scheduleZoomSave()
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
        }

        muteBar.translatesAutoresizingMaskIntoConstraints = false
        muteBar.isHidden = cropSelectionMode
        muteBar.onMute = { [weak self] duration in
            SettingsStore.shared.mute(for: duration)
            self?.closePopup()
        }

        cropSelectionView.translatesAutoresizingMaskIntoConstraints = false
        cropSelectionView.isHidden = !cropSelectionMode
        cropSelectionView.onSelectionChanged = { [weak self] in
            self?.cropActionBar.setSaveEnabled(self?.cropSelectionView.hasValidSelection ?? false)
        }

        cropActionBar.translatesAutoresizingMaskIntoConstraints = false
        cropActionBar.isHidden = !cropSelectionMode
        cropActionBar.setSaveEnabled(false)
        cropActionBar.onCancel = { [weak self] in
            self?.cancelCropSelection()
        }
        cropActionBar.onSave = { [weak self] in
            self?.saveCropSelection()
        }

        content.addSubview(thumbnailView)
        content.addSubview(playerView)
        content.addSubview(clickCatcher)
        content.addSubview(muteBar)
        content.addSubview(cropSelectionView)
        content.addSubview(cropActionBar)

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

            cropSelectionView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            cropSelectionView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            cropSelectionView.topAnchor.constraint(equalTo: content.topAnchor),
            cropSelectionView.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            cropActionBar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -8),
            cropActionBar.topAnchor.constraint(equalTo: content.topAnchor, constant: 8),
        ])

        if let thumbnailDataURI, let image = imageFromDataURI(thumbnailDataURI) {
            thumbnailView.image = image
        }
    }

    private func setupCloseHandlers(autoCloseSeconds: Double) {
        self.autoCloseSeconds = autoCloseSeconds

        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                if self?.cropSelectionMode == true {
                    self?.cancelCropSelection()
                } else {
                    self?.closePopup()
                }
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
        zoomSaveTimer?.invalidate()
        zoomSaveTimer = nil
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
        if rememberZoom, !cropSelectionMode {
            let zoomState = playerView.currentZoomState
            onWillClose?(zoomState.scale, zoomState.panOffset)
        }
        playerView.stop()
        orderOut(nil)
        onClose()
    }

    /// Persists the current zoom/pan shortly after the last interaction, so a
    /// remembered zoom survives even when the app never reaches `closePopup()`
    /// (e.g. a crash or force-quit). Debounced to avoid writing on every event.
    private func scheduleZoomSave() {
        guard rememberZoom, !cropSelectionMode else { return }
        zoomSaveTimer?.invalidate()
        zoomSaveTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            guard let self else { return }
            let zoomState = self.playerView.currentZoomState
            self.onWillClose?(zoomState.scale, zoomState.panOffset)
        }
    }

    private func cancelCropSelection() {
        onCropCancel?()
        closePopup()
    }

    private func saveCropSelection() {
        guard let normalized = cropSelectionView.normalizedCrop() else { return }
        let pixelSize = cropSelectionView.selectionPixelSize
        onCropSave?(normalized, pixelSize)
        closePopup()
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
        button.image = muteButtonImage(leadingPadding: 6)
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

    private func muteButtonImage(leadingPadding: CGFloat) -> NSImage? {
        guard let symbol = NSImage(
            systemSymbolName: "bell.slash.fill",
            accessibilityDescription: "Stummschalten"
        ) else { return nil }

        let configured = symbol.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        ) ?? symbol
        let iconSize = configured.size
        let canvasSize = NSSize(
            width: iconSize.width + leadingPadding,
            height: iconSize.height
        )

        let image = NSImage(size: canvasSize, flipped: false) { rect in
            let drawRect = NSRect(
                x: leadingPadding,
                y: (rect.height - iconSize.height) / 2,
                width: iconSize.width,
                height: iconSize.height
            )
            configured.draw(in: drawRect)
            return true
        }
        image.isTemplate = true
        return image
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

/// Cancel / Save buttons shown during crop selection (top-right of the popup).
private final class CropActionBarView: NSView {
    var onCancel: (() -> Void)?
    var onSave: (() -> Void)?

    private let stack = NSStackView()
    private let saveButton: NSButton

    override init(frame frameRect: NSRect) {
        saveButton = CropActionBarView.makeButton(title: "Speichern")
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        saveButton = CropActionBarView.makeButton(title: "Speichern")
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        let cancelButton = Self.makeButton(title: "Abbrechen")
        cancelButton.target = self
        cancelButton.action = #selector(cancelTapped)

        saveButton.target = self
        saveButton.action = #selector(saveTapped)

        stack.orientation = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(cancelButton)
        stack.addArrangedSubview(saveButton)
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private static func makeButton(title: String) -> NSButton {
        let button = FirstMouseButton()
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        button.layer?.cornerRadius = 6
        button.contentTintColor = .white
        button.title = title
        button.font = .systemFont(ofSize: 11, weight: .semibold)
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            ]
        )
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 72).isActive = true
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return button
    }

    func setSaveEnabled(_ enabled: Bool) {
        saveButton.isEnabled = enabled
        saveButton.alphaValue = enabled ? 1.0 : 0.45
    }

    @objc private func cancelTapped() {
        onCancel?()
    }

    @objc private func saveTapped() {
        onSave?()
    }
}

/// An `NSButton` that fires on the first click even when its window is not key,
/// which is required inside the non-activating popup panel.
private final class FirstMouseButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
