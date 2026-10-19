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
    /// Centered while the stream starts; gone with the first frame or when the stream is unreachable.
    private let loadingLabel = NSTextField(labelWithString: "Stream wird geladen …")
    /// Stills mode: the stream yields no picture (e.g. AV1), so camera snapshots stand in for it.
    private let stillsNotice = PopupNoticeView()
    private let snapshotSource: (() async -> NSImage?)?
    private var stillsTimer: Timer?
    private var autoCloseTimer: Timer?
    private var zoomSaveTimer: Timer?
    private var escapeMonitor: Any?
    private var resizeObserver: NSObjectProtocol?
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

    // MARK: Layout "Miniatur" (docs/design/popup-miniatur.md)

    /// Layout "Miniatur": the controller drives hover, size and closing; the timer really pauses.
    let isMiniature: Bool
    /// Compact = only the video or still, no chip, buttons, pill, notices or menus.
    private(set) var isCompact = false
    /// Chip, buttons, pill, menus (above the click catcher; empty areas pass clicks through).
    private let chromeLayer = PassthroughView()
    /// Loading text and notices (never take clicks).
    private let hintLayer = PassthroughView(passesAll: true)
    /// Miniature: the card with everything on it (it slides; the window clips at the screen edge).
    private let card = NSView()
    /// Window frame before the slide widened it to the screen edge; card positions in the wide window.
    private var slide: (base: NSRect, home: NSPoint, outside: NSPoint)?
    /// A newer `prepareSlide` replaces the running slide (its end no longer shrinks the window).
    private var slideToken = 0
    /// Miniature: black background and ring as views, so they slide with the content.
    private let backgroundView = PassthroughView(passesAll: true)
    private let ringView = PassthroughView(passesAll: true)
    /// Pointer entered (true) or left (false) the popup (tracking area of the click catcher).
    var onHoverChange: ((Bool) -> Void)?
    /// Set by the controller: closing slides the miniature out first and then calls `finishClose()`.
    var closeInterceptor: (() -> Void)?
    /// Set by the controller: whether a click on the compact popup closes it (a miniature, also
    /// while the hover bar runs) or does nothing (it grows already).
    var compactClickCloses: (() -> Bool)?
    private var isClosing = false
    private var isClosed = false
    /// A picture is shown: the event still, the first video frame or a camera still.
    private var hasPicture = false
    private var pictureWaiters: [() -> Void] = []
    private var isRunningModal = false
    private var clock: AutoCloseClock?
    private var clockPaused = false
    /// Width the saved zoom/pan refers to (the popup's full size); nil = as before (Layout "Voll").
    var zoomReferenceWidth: CGFloat?

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
        snapshotSource: (() async -> NSImage?)? = nil,
        onWillClose: ((CGFloat, CGPoint) -> Void)? = nil,
        onCropSave: ((CameraCrop, CGSize) -> Void)? = nil,
        onCropCancel: (() -> Void)? = nil,
        miniature: Bool = false,
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
        self.snapshotSource = snapshotSource
        self.onWillClose = onWillClose
        self.onCropSave = onCropSave
        self.onCropCancel = onCropCancel
        self.isMiniature = miniature && !cropSelectionMode

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
        if isMiniature {
            playerView.keepsViewportOnResize = true
            // Hover and the expanded state pause it (`setAutoClosePaused`).
            clock = AutoCloseClock(total: 0, now: Date())
            setCompact(true, animated: false)
        }
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
            // Miniature: the saved pan refers to the full size, the player may be smaller now.
            if zoomReferenceWidth != nil { contentView?.layoutSubtreeIfNeeded() }
            let factor = zoomFactor(toReference: false)
            playerView.applyZoomState(
                scale: CGFloat(initialZoom.scale),
                panOffset: CGPoint(x: initialZoom.panOffsetX * factor, y: initialZoom.panOffsetY * factor)
            )
        }

        playerView.play(urlString: streamURL, soundEnabled: soundEnabled) { [weak self] in
            guard let self else { return }
            self.pictureShown()
            self.stopStills()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                self.playerView.animator().alphaValue = 1
                self.thumbnailView.animator().alphaValue = 0
                self.loadingLabel.animator().alphaValue = 0
            }
        }
    }

    private func setupContent(thumbnailDataURI: String?) {
        guard let root = contentView else { return }

        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.black.cgColor
        root.layer?.cornerRadius = Self.cornerRadius
        root.layer?.masksToBounds = true
        let content: NSView
        if isMiniature {
            // Miniature: everything lives on a card that slides in from the screen edge and out
            // again (`prepareSlide`), so the black background and the ring are views on it.
            root.layer?.backgroundColor = NSColor.clear.cgColor
            card.frame = root.bounds
            card.autoresizingMask = [.width, .height]
            card.wantsLayer = true
            root.addSubview(card)
            content = card
            addFullSizeView(backgroundView, to: content)
            backgroundView.wantsLayer = true
            backgroundView.layer?.backgroundColor = NSColor.black.cgColor
            backgroundView.layer?.cornerRadius = Self.cornerRadius
        } else {
            content = root
        }

        thumbnailView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailView.wantsLayer = true
        thumbnailView.layer?.cornerRadius = Self.cornerRadius
        thumbnailView.layer?.masksToBounds = true
        thumbnailView.alphaValue = 1
        // A full-size camera still would otherwise push its pixel size onto the window
        // (NSImageView's intrinsic size) – the image scales into the popup instead.
        for orientation in [NSLayoutConstraint.Orientation.horizontal, .vertical] {
            thumbnailView.setContentCompressionResistancePriority(.defaultLow, for: orientation)
            thumbnailView.setContentHuggingPriority(.defaultLow, for: orientation)
        }

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
                // Miniature: a click (also a quick one before it grows) closes it; while it grows
                // the click is ignored.
                if self.isCompact {
                    if self.compactClickCloses?() ?? true { self.closePopup() }
                    return
                }
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
            // Zoom and pan only at full size, not in the miniature.
            clickCatcher.onScroll = { [weak self] delta, location in
                guard let self, !self.isCompact else { return }
                self.playerView.zoom(by: delta * 0.01, at: location)
                self.scheduleZoomSave()
            }
            clickCatcher.onMagnify = { [weak self] magnification, location in
                guard let self, !self.isCompact else { return }
                self.playerView.zoom(by: magnification, at: location)
                self.scheduleZoomSave()
            }
            clickCatcher.onDrag = { [weak self] delta in
                guard let self, !self.isCompact else { return }
                self.playerView.pan(by: delta)
                self.scheduleZoomSave()
            }
            clickCatcher.isZoomedIn = { [weak self] in
                self?.playerView.isZoomedIn ?? false
            }
            clickCatcher.onMouseEnter = { [weak self] in
                guard let self else { return }
                if self.isMiniature {
                    self.onHoverChange?(true)
                } else {
                    self.pauseAutoClose()
                }
            }
            clickCatcher.onMouseExit = { [weak self] in
                guard let self else { return }
                if self.isMiniature {
                    self.onHoverChange?(false)
                } else {
                    self.resumeAutoClose()
                }
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
        // "Voll" and crop selection: the loading text under the click catcher and the crop
        // selection, the notices above them (they take clicks).
        if !isMiniature { content.addSubview(loadingLabel) }
        content.addSubview(clickCatcher)
        content.addSubview(cropSelectionView)
        content.addSubview(cropActionBar)
        // Miniature: loading text and notices in one layer (never takes clicks); the compact
        // miniature hides it. "Voll": the notices directly, they take clicks as before.
        let hintParent: NSView = isMiniature ? hintLayer : content
        if isMiniature {
            addFullSizeLayer(hintLayer, to: content)
            hintLayer.addSubview(loadingLabel)
            hintLayer.addSubview(streamNotice)
            hintLayer.addSubview(stillsNotice)
        } else {
            content.addSubview(streamNotice)
            content.addSubview(stillsNotice)
        }
        playerView.onUnavailable = { [weak self] text in
            self?.loadingLabel.isHidden = true
            self?.streamNotice.show(text)
        }
        // Overlay chrome above everything (the compact miniature hides it).
        addFullSizeLayer(chromeLayer, to: content)
        playerView.onNoPicture = { [weak self] isAV1 in
            self?.startStills(isAV1: isAV1)
        }

        loadingLabel.translatesAutoresizingMaskIntoConstraints = false
        loadingLabel.font = .systemFont(ofSize: 13, weight: .medium)
        loadingLabel.textColor = NSColor.white.withAlphaComponent(0.75)
        loadingLabel.alignment = .center

        NSLayoutConstraint.activate([
            loadingLabel.centerXAnchor.constraint(equalTo: hintParent.centerXAnchor),
            loadingLabel.centerYAnchor.constraint(equalTo: hintParent.centerYAnchor),
            streamNotice.centerXAnchor.constraint(equalTo: hintParent.centerXAnchor),
            streamNotice.centerYAnchor.constraint(equalTo: hintParent.centerYAnchor),
            streamNotice.widthAnchor.constraint(lessThanOrEqualTo: hintParent.widthAnchor, constant: -20),
            stillsNotice.centerXAnchor.constraint(equalTo: hintParent.centerXAnchor),
            stillsNotice.topAnchor.constraint(equalTo: hintParent.topAnchor, constant: 42),
            stillsNotice.widthAnchor.constraint(lessThanOrEqualTo: hintParent.widthAnchor, constant: -20),

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
            hasPicture = true
        }
        if isMiniature {
            // On top like the layer border it replaces (the overlays go into their layers).
            addFullSizeView(ringView, to: content)
            ringView.wantsLayer = true
            ringView.layer?.cornerRadius = Self.cornerRadius
            ringView.layer?.borderWidth = 1
            ringView.layer?.borderColor = Tokens.popupRing.light.nsColor.cgColor
        }
        setupOverlay(in: content)
    }

    /// Template B chrome (docs/design/popup.md): event chip, mute + close, mute menu, button pill.
    private func setupOverlay(in content: NSView) {
        if !isMiniature {
            content.layer?.borderWidth = 1
            content.layer?.borderColor = Tokens.popupRing.light.nsColor.cgColor
        }
        guard let overlay else { return }

        let close = CircleIconButton(icon: .close, iconSize: 11, diameter: 24,
                                     fill: Tokens.overlay, tint: Tokens.white, label: "Schließen")
        close.target = self
        close.action = #selector(closeTapped)
        let mute = CircleIconButton(icon: .bellSlash, iconSize: 13, diameter: 24,
                                    fill: Tokens.overlay, tint: Tokens.white, label: "Diese Kamera stummschalten")
        mute.target = self
        mute.action = #selector(muteTapped)
        let settingsButton = CircleIconButton(icon: .gear, iconSize: 13, diameter: 24,
                                              fill: Tokens.overlay, tint: Tokens.white, label: "Einstellungen dieser Kamera")
        settingsButton.target = self
        settingsButton.action = #selector(settingsTapped)
        let menu = PopupMuteMenuView(cameraName: overlay.cameraName, options: overlay.muteOptions)
        menu.isHidden = true
        menu.onPick = { [weak self] duration in
            overlay.onMute(duration)
            self?.closePopup()
        }

        let chrome = chromeLayer
        chrome.addSubview(close)
        chrome.addSubview(mute)
        chrome.addSubview(settingsButton)
        var constraints = [
            close.trailingAnchor.constraint(equalTo: chrome.trailingAnchor, constant: -10),
            close.topAnchor.constraint(equalTo: chrome.topAnchor, constant: 10),
            mute.trailingAnchor.constraint(equalTo: chrome.trailingAnchor, constant: -40),
            mute.topAnchor.constraint(equalTo: chrome.topAnchor, constant: 10),
            settingsButton.trailingAnchor.constraint(equalTo: chrome.trailingAnchor, constant: -70),
            settingsButton.topAnchor.constraint(equalTo: chrome.topAnchor, constant: 10),
        ]
        if let chipText = overlay.chip {
            let chip = OverlayChipView(text: chipText)
            chrome.addSubview(chip)
            // Centred; on a narrow popup it moves left (and truncates) before touching the buttons.
            let centered = chip.centerXAnchor.constraint(equalTo: chrome.centerXAnchor)
            centered.priority = .defaultHigh
            constraints += [
                centered,
                chip.leadingAnchor.constraint(greaterThanOrEqualTo: chrome.leadingAnchor, constant: 10),
                chip.centerYAnchor.constraint(equalTo: close.centerYAnchor),
                chip.trailingAnchor.constraint(lessThanOrEqualTo: settingsButton.leadingAnchor, constant: -8),
            ]
        }
        var leading: [NSView] = []
        if let talk = overlay.talk {
            let controls = PopupTalkControls(content: talk)
            leading = [controls.soundButton, controls.talkButton]
            controls.onMenuOpened = { [weak self] in self?.muteMenu?.isHidden = true }
            talkControls = controls
            // The stack resizes popups (also animated): the talk button follows the width.
            let circles = 1 + (overlay.sound == nil ? 0 : 1) + min(actions.count, WebhookMapping.maxActions)
            controls.fit(popupWidth: frame.width, circles: circles)
            resizeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification, object: self, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.talkControls?.fit(popupWidth: self.frame.width, circles: circles)
                }
            }
        }
        if let sound = overlay.sound {
            let button = CameraSoundButton(content: PopupSoundContent(enabled: sound.enabled) { [weak self] enabled in
                self?.playerView.setSoundEnabled(enabled)
                sound.onToggle(enabled)
            })
            leading.append(button)
        }
        if !actions.isEmpty || !leading.isEmpty {
            let pill = ActionPillView(actions: actions, leadingViews: leading)
            pill.onAction = { [weak self] action, button in
                self?.run(action, from: button)
            }
            chrome.addSubview(pill)
            constraints += [
                pill.centerXAnchor.constraint(equalTo: chrome.centerXAnchor),
                pill.bottomAnchor.constraint(equalTo: chrome.bottomAnchor, constant: -12),
            ]
            talkControls?.install(in: chrome, above: pill)
        }
        // Last, so the open menu lies above the pill and the chip.
        chrome.addSubview(menu)
        constraints += [
            menu.trailingAnchor.constraint(equalTo: chrome.trailingAnchor, constant: -10),
            menu.topAnchor.constraint(equalTo: chrome.topAnchor, constant: 40),
        ]
        NSLayoutConstraint.activate(constraints)
        muteMenu = menu
    }

    /// No picture from the stream: show a fresh camera still every second instead (sound,
    /// talk and buttons keep working). Ends with the first real picture or the popup.
    private func startStills(isAV1: Bool) {
        loadingLabel.isHidden = true
        stillsNotice.show(isAV1
            ? "Standbilder – AV1 wird nicht unterstützt (Protect: Super Encoding auf „Auto“)"
            : "Standbilder – Livebild nicht abspielbar (Kamera-Einstellung, z. B. AV1?)",
            persistent: true)
        guard let snapshotSource, stillsTimer == nil else { return }
        var loading = false
        let refresh = { [weak self] in
            guard !loading else { return }
            loading = true
            Task { @MainActor [weak self] in
                let image = await snapshotSource()
                loading = false
                guard let self, self.stillsTimer != nil, let image else { return }
                self.thumbnailView.image = image
                self.thumbnailView.alphaValue = 1
                self.pictureShown()
            }
        }
        let timer = Timer(timeInterval: 1, repeats: true) { _ in refresh() }
        RunLoop.main.add(timer, forMode: .common)
        stillsTimer = timer
        refresh()
    }

    private func stopStills() {
        stillsTimer?.invalidate()
        stillsTimer = nil
        stillsNotice.hide()
    }

    @objc private func closeTapped() {
        closePopup()
    }

    @objc private func settingsTapped() {
        muteMenu?.isHidden = true
        overlay?.onOpenSettings()
    }

    @objc private func muteTapped() {
        muteMenu?.isHidden.toggle()
        if muteMenu?.isHidden == false { _ = talkControls?.closeMenu() }
    }

    /// Calls the button's webhook and/or plays its sound at this camera, both at once; the popup
    /// stays open. Optional confirmation first.
    private func run(_ action: CameraAction, from button: CircleIconButton) {
        if action.confirmBeforeRun {
            let alert = NSAlert()
            alert.messageText = "„\(action.trimmedTitle)“ ausführen?"
            alert.addButton(withTitle: "Ausführen")
            alert.addButton(withTitle: "Abbrechen")
            NSApp.activate(ignoringOtherApps: true)
            isRunningModal = true
            let response = alert.runModal()
            isRunningModal = false
            guard response == .alertFirstButtonReturn else { return }
        }
        // Sound only where this popup can talk (camera with speaker); errors show as the popup notice.
        var soundStart: PlayStart?
        if let entryId = overlay?.talk?.entryId,
           let announcement = action.soundId.flatMap(SoundStore.shared.settings.announcement(id:)) {
            soundStart = TalkbackService.shared.play(announcement, entryId: entryId)
        }
        guard action.requestURL != nil else {
            // Sound only: the tick only when the announcement really started.
            button.showResult(error: Self.soundError(soundStart))
            return
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

    /// nil = started; otherwise the reason for the button's tooltip (orange instead of the tick).
    private static func soundError(_ start: PlayStart?) -> String? {
        switch start {
        case .started?: return nil
        case .busy?: return "Es wird gerade gesprochen."
        case .fileMissing?: return "Die Datei der Ansage fehlt."
        case .noCamera?, nil: return "Ton nicht verfügbar."
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
        if isMiniature {
            clock?.restart(total: seconds, at: Date())
            armClockTimer()
            return
        }
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

    /// This popup is talking or sending an announcement (never replaced or auto-closed then).
    var isBusy: Bool { talkControls?.isBusy == true }

    /// Auto-close waits while this popup talks or sends an announcement.
    private func autoCloseFired() {
        if talkControls?.isBusy == true {
            if isMiniature {
                clock?.setRemaining(5, at: Date())
                armClockTimer()
            } else {
                scheduleAutoClose(after: 5)
            }
            return
        }
        closePopup()
    }

    /// Miniature: one timer for the clock's remaining time, none while paused.
    private func armClockTimer() {
        autoCloseTimer?.invalidate()
        autoCloseTimer = nil
        guard !isClosing, let clock, clock.isEnabled, !clock.isPaused else { return }
        let timer = Timer(timeInterval: max(clock.remaining(at: Date()), 0.01), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.autoCloseFired() }
        }
        RunLoop.main.add(timer, forMode: .common)
        autoCloseTimer = timer
    }

    /// Miniature: hover and the expanded state pause the auto-close timer, it resumes where it stopped.
    func setAutoClosePaused(_ paused: Bool) {
        guard isMiniature, paused != clockPaused else { return }
        clockPaused = paused
        clock?.setPaused(paused, at: Date())
        armClockTimer()
    }

    /// Miniature: remaining and full auto-close time (total 0 = never closes).
    var autoCloseProgress: (remaining: TimeInterval, total: TimeInterval) {
        guard let clock else { return (0, 0) }
        return (clock.remaining(at: Date()), clock.total)
    }

    /// The expanded popup stays big although the pointer left it: a menu is open, it talks or sends
    /// an announcement, or a confirmation is shown.
    var isHeldOpen: Bool {
        muteMenu?.isHidden == false || talkControls?.isMenuOpen == true || isBusy || isRunningModal
    }

    /// Compact (miniature): overlays, notices and menus disappear at once. Full: they fade in (180 ms).
    func setCompact(_ compact: Bool, animated: Bool) {
        guard isMiniature else { return }
        isCompact = compact
        if compact {
            muteMenu?.isHidden = true
            _ = talkControls?.closeMenu()
            for layer in [chromeLayer, hintLayer] {
                layer.isHidden = true
                layer.alphaValue = 0
            }
            // A zoomed popup would keep the open-hand cursor in the miniature.
            invalidateCursorRects(for: clickCatcher)
            return
        }
        for layer in [chromeLayer, hintLayer] {
            layer.isHidden = false
            if animated {
                layer.alphaValue = 0
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = MiniatureTiming.overlayFadeIn
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    layer.animator().alphaValue = 1
                }
            } else {
                layer.alphaValue = 1
            }
        }
        invalidateCursorRects(for: clickCatcher)
    }

    private func addFullSizeView(_ view: NSView, to content: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            view.topAnchor.constraint(equalTo: content.topAnchor),
            view.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
    }

    /// Miniature: the content (video, still, background, ring) slides in from beyond the outer edge
    /// (`side`) or out beyond it, inside the window and cut off at its rounded edge; the window
    /// itself stands still, so nothing shows on a neighbouring screen. No shadow while it slides
    /// (it would show the empty window's outline).
    /// Miniature: `action` runs once a picture is shown (event still, first video frame or camera
    /// still), at the latest after `timeout` – so a miniature never slides in as an empty black card.
    func whenPictureShown(timeout: TimeInterval, _ action: @escaping () -> Void) {
        if hasPicture {
            action()
            return
        }
        var done = false
        let once = {
            guard !done else { return }
            done = true
            action()
        }
        pictureWaiters.append(once)
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { once() }
    }

    private func pictureShown() {
        hasPicture = true
        let waiters = pictureWaiters
        pictureWaiters = []
        waiters.forEach { $0() }
    }

    /// Room for the card's shadow around it while it slides.
    private static let slideShadowRoom: CGFloat = 16

    /// Miniature, start of the slide-in or slide-out: the window reaches from the card to the outer
    /// edge of `screenFrame` (the real screen edge, never beyond: nothing on a neighbouring screen),
    /// the strip in between is transparent. The card keeps its size and gets its own shadow instead
    /// of the window's. `outside`: the card waits completely beyond the edge (slide-in).
    func prepareSlide(side: PopupAnchor.Horizontal, screenFrame: CGRect, outside: Bool) {
        guard isMiniature, let root = contentView else { return }
        let base = slide?.base ?? frame
        let room = Self.slideShadowRoom
        var wide = base.insetBy(dx: -room, dy: -room)
        switch side {
        case .leading:
            wide = NSRect(x: screenFrame.minX, y: wide.minY, width: wide.maxX - screenFrame.minX, height: wide.height)
        case .trailing, .center:
            wide.size.width = screenFrame.maxX - wide.minX
        }
        // Never beyond the screen (a small edge margin leaves less shadow room there).
        wide = wide.intersection(screenFrame)
        let home = NSPoint(x: base.minX - wide.minX, y: base.minY - wide.minY)
        let beyond = NSPoint(x: side == .leading ? -(base.width + room) : wide.width + room, y: home.y)
        slide = (base, home, beyond)
        slideToken += 1

        hasShadow = false
        card.autoresizingMask = []
        if let layer = card.layer {
            layer.shadowColor = NSColor.black.cgColor
            layer.shadowOpacity = 0.35
            layer.shadowRadius = 8
            layer.shadowOffset = CGSize(width: 0, height: -3)
            layer.shadowPath = CGPath(
                roundedRect: CGRect(origin: .zero, size: base.size),
                cornerWidth: Self.cornerRadius, cornerHeight: Self.cornerRadius, transform: nil
            )
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Only the screen edge cuts the card, not a rounded window corner.
        root.layer?.cornerRadius = 0
        setFrame(wide, display: false)
        card.frame = NSRect(origin: outside ? beyond : home, size: base.size)
        CATransaction.commit()
        displayIfNeeded()
    }

    /// Miniature: the card slides in one piece from beyond the screen edge to its place (`in`,
    /// then the window shrinks back to the miniature frame) or out beyond the edge. Needs
    /// `prepareSlide` first. Not `animated` ("Bewegung reduzieren"): at once.
    func slideCard(in slidingIn: Bool, curve: CAMediaTimingFunction, animated: Bool = true, completion: @escaping () -> Void) {
        guard let slide else {
            completion()
            return
        }
        let target = slidingIn ? slide.home : slide.outside
        let token = slideToken
        let finish = { [weak self] in
            guard let self, self.slideToken == token else { return }
            if slidingIn { self.endSlide() }
            completion()
        }
        guard animated else {
            card.setFrameOrigin(target)
            finish()
            return
        }
        // Next pass: the card layer has taken its new place, the animation starts from there.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = MiniatureTiming.move
                context.timingFunction = curve
                self.card.animator().setFrameOrigin(target)
            }, completionHandler: {
                MainActor.assumeIsolated { finish() }
            })
        }
    }

    /// Back to the miniature frame without a visible jump: the window shrinks to the card.
    private func endSlide() {
        guard let slide, let root = contentView else { return }
        self.slide = nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        setFrame(slide.base, display: false)
        card.frame = root.bounds
        card.autoresizingMask = [.width, .height]
        card.layer?.shadowOpacity = 0
        root.layer?.cornerRadius = Self.cornerRadius
        CATransaction.commit()
        displayIfNeeded()
        hasShadow = true
        invalidateShadow()
    }

    /// The overlay layers fill the popup. Miniature: only below the window's own size priority, so
    /// the minimum size of chip, buttons, pill and menus (wider than a 200 pt miniature) can never
    /// enlarge the window – it would grow right and up past the edge margin. The layers are hidden
    /// then; at full size nothing conflicts.
    private func addFullSizeLayer(_ layer: NSView, to content: NSView) {
        layer.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(layer)
        let edges = [
            layer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            layer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            layer.topAnchor.constraint(equalTo: content.topAnchor),
            layer.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ]
        if isMiniature {
            for edge in edges { edge.priority = NSLayoutConstraint.Priority(NSLayoutConstraint.Priority.windowSizeStayPut.rawValue - 10) }
        }
        NSLayoutConstraint.activate(edges)
    }

    /// Saved pan -> current player size (`toReference: false`) or back (`true`).
    private func zoomFactor(toReference: Bool) -> CGFloat {
        guard let reference = zoomReferenceWidth, reference > 0 else { return 1 }
        let current = playerView.bounds.width > 0 ? playerView.bounds.width : frame.width
        guard current > 0 else { return 1 }
        return toReference ? reference / current : current / reference
    }

    func extendAutoClose(seconds: Double) {
        autoCloseSeconds = seconds
        scheduleAutoClose(after: seconds)
    }

    /// Closes the popup. Miniature: the controller slides it out first and then calls `finishClose()`.
    func closePopup() {
        if let closeInterceptor, !isClosing {
            isClosing = true
            autoCloseTimer?.invalidate()
            autoCloseTimer = nil
            setCompact(true, animated: false)
            closeInterceptor()
            return
        }
        finishClose()
    }

    /// Releases everything and orders the window out (after the slide-out in the miniature layout).
    func finishClose() {
        guard !isClosed else { return }
        isClosed = true
        isClosing = true
        if let resizeObserver {
            NotificationCenter.default.removeObserver(resizeObserver)
            self.resizeObserver = nil
        }
        talkControls?.popupClosed()
        autoCloseTimer?.invalidate()
        autoCloseTimer = nil
        zoomSaveTimer?.invalidate()
        zoomSaveTimer = nil
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
        if rememberZoom, !cropSelectionMode {
            saveZoomState()
        }
        stopStills()
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
            self?.saveZoomState()
        }
    }

    /// Miniature: stored relative to the full size, whatever size the popup has right now.
    private func saveZoomState() {
        let zoomState = playerView.currentZoomState
        let factor = zoomFactor(toReference: true)
        onWillClose?(zoomState.scale, CGPoint(x: zoomState.panOffset.x * factor, y: zoomState.panOffset.y * factor))
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

/// Container whose own area lets clicks through to the click catcher below; its subviews still
/// get them (`passesAll`: they never do).
private final class PassthroughView: NSView {
    private let passesAll: Bool

    init(passesAll: Bool = false) {
        self.passesAll = passesAll
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !passesAll else { return nil }
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
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
