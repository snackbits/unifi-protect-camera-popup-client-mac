import AppCore
import AppKit

final class PopupWindow: NSPanel {
    private static let cornerRadius: CGFloat = 12

    private let thumbnailView = NSImageView()
    private let playerView = VLCPlayerContainerView()
    private let clickCatcher = ClickCatchingView()
    private var muteMenu: PopupMuteMenuView?
    private var talkControls: PopupTalkControls?
    private let cropSelectionView = CropSelectionView()
    private let cropActionBar = CropActionBarView()
    /// Stream not reachable on the current route (away, camera not in the tunnel).
    private let streamNotice = PopupNoticeView()
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
    private let actions: [CameraAction]
    private let overlay: PopupOverlayContent?
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
        actions: [CameraAction] = [],
        overlay: PopupOverlayContent? = nil,
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
        self.actions = cropSelectionMode ? [] : actions
        self.overlay = cropSelectionMode ? nil : overlay
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
                if self.talkControls?.closeMenu() == true {
                    return
                }
                // An open mute menu takes the first click away from the video.
                if self.muteMenu?.isHidden == false {
                    self.muteMenu?.isHidden = true
                    return
                }
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
                self?.talkControls?.pointerInside(true)
            }
            clickCatcher.onMouseExit = { [weak self] in
                self?.resumeAutoClose()
                self?.talkControls?.pointerInside(false)
            }
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
        content.addSubview(cropSelectionView)
        content.addSubview(cropActionBar)
        content.addSubview(streamNotice)
        playerView.onUnavailable = { [weak self] text in self?.streamNotice.show(text) }

        NSLayoutConstraint.activate([
            streamNotice.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            streamNotice.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            streamNotice.widthAnchor.constraint(lessThanOrEqualTo: content.widthAnchor, constant: -20),

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
        setupOverlay(in: content)
    }

    /// Template B chrome (docs/design/popup.md): event chip, mute + close, mute menu, button pill.
    private func setupOverlay(in content: NSView) {
        content.layer?.borderWidth = 1
        content.layer?.borderColor = Tokens.popupRing.light.nsColor.cgColor
        guard let overlay else { return }

        let close = CircleIconButton(icon: .close, iconSize: 11, diameter: 24,
                                     fill: Tokens.overlay, tint: Tokens.white, label: "Schließen")
        close.target = self
        close.action = #selector(closeTapped)
        let mute = CircleIconButton(icon: .bellSlash, iconSize: 13, diameter: 24,
                                    fill: Tokens.overlay, tint: Tokens.white, label: "Diese Kamera stummschalten")
        mute.target = self
        mute.action = #selector(muteTapped)
        let menu = PopupMuteMenuView(cameraName: overlay.cameraName, options: overlay.muteOptions)
        menu.isHidden = true
        menu.onPick = { [weak self] duration in
            overlay.onMute(duration)
            self?.closePopup()
        }

        content.addSubview(close)
        content.addSubview(mute)
        var constraints = [
            close.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            close.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            mute.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -40),
            mute.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
        ]
        if let chipText = overlay.chipText {
            let chip = OverlayChipView(text: chipText)
            content.addSubview(chip)
            constraints += [
                chip.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
                chip.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
                chip.trailingAnchor.constraint(lessThanOrEqualTo: mute.leadingAnchor, constant: -8),
            ]
        }
        var leading: [NSView] = []
        if let talk = overlay.talk {
            let controls = PopupTalkControls(content: talk)
            leading = [controls.soundButton, controls.talkButton]
            controls.onMenuOpened = { [weak self] in self?.muteMenu?.isHidden = true }
            talkControls = controls
        }
        if !actions.isEmpty || !leading.isEmpty {
            let pill = ActionPillView(actions: actions, leadingViews: leading)
            pill.onAction = { [weak self] action, button in
                self?.run(action, from: button)
            }
            content.addSubview(pill)
            constraints += [
                pill.centerXAnchor.constraint(equalTo: content.centerXAnchor),
                pill.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            ]
            talkControls?.install(in: content, above: pill)
        }
        // Last, so the open menu lies above the pill and the chip.
        content.addSubview(menu)
        constraints += [
            menu.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            menu.topAnchor.constraint(equalTo: content.topAnchor, constant: 40),
        ]
        NSLayoutConstraint.activate(constraints)
        muteMenu = menu
    }

    @objc private func closeTapped() {
        closePopup()
    }

    @objc private func muteTapped() {
        muteMenu?.isHidden.toggle()
        if muteMenu?.isHidden == false { _ = talkControls?.closeMenu() }
    }

    /// Calls the button's webhook; the popup stays open. Optional confirmation first.
    private func run(_ action: CameraAction, from button: CircleIconButton) {
        if action.confirmBeforeRun {
            let alert = NSAlert()
            alert.messageText = "„\(action.trimmedTitle)“ ausführen?"
            alert.addButton(withTitle: "Ausführen")
            alert.addButton(withTitle: "Abbrechen")
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        button.showRunning()
        Task {
            do {
                try await CameraActionService.trigger(action)
                button.showResult(error: nil)
            } catch {
                NSLog("Camera action \"\(action.trimmedTitle)\" failed: \(error.localizedDescription)")
                button.showResult(error: error.localizedDescription)
            }
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
            self?.autoCloseFired()
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
            autoCloseFired()
            return
        }

        autoCloseTimer = Timer.scheduledTimer(withTimeInterval: remaining, repeats: false) { [weak self] _ in
            self?.autoCloseFired()
        }
    }

    /// Auto-close waits while this popup talks or sends an announcement.
    private func autoCloseFired() {
        if talkControls?.isBusy == true {
            scheduleAutoClose(after: 5)
            return
        }
        closePopup()
    }

    func extendAutoClose(seconds: Double) {
        autoCloseSeconds = seconds
        scheduleAutoClose(after: seconds)
    }

    func closePopup() {
        talkControls?.popupClosed()
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
class FirstMouseButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
