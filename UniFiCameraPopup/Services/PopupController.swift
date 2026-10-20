import AppCore
import AppKit
import Combine
import ProtectKit

@MainActor
final class PopupController {
    static let shared = PopupController()

    /// A popup that is currently on screen. The order of `activePopups` is the
    /// stacking order and is kept stable: a re-triggering camera only restarts
    /// its timeout, it is never moved within the stack.
    private struct ActivePopup {
        /// This window (an entry may briefly have a second one while the first slides out).
        let id: UUID
        /// The mapping entry shown. Protect-only entries have no webhook slug,
        /// so popups are keyed by entry, never by webhook id.
        let entryId: UUID
        let window: PopupWindow
        let size: CGSize
        /// The position used when only a single popup is shown.
        let position: PopupPosition
        /// Crop selection keeps its size; the stack never resizes it.
        var fixedSize = false
        /// Opened in the layout "Miniatur" (`MiniatureStackPresenter` places it).
        var isMiniature = false
    }

    private var activePopups: [ActivePopup] = []
    /// Frame each popup was last sent to (animation target). An unchanged target never restarts
    /// a running 300 ms animation.
    private var targetFrames: [UUID: NSRect] = [:]
    private let settings = SettingsStore.shared
    private var screenObserver: NSObjectProtocol?
    private var layoutModeObserver: AnyCancellable?
    private var positionObserver: AnyCancellable?
    private lazy var miniatures = MiniatureStackPresenter { [unowned self] in self.miniatureEnvironment() }

    private init() {
        // Display added/removed, resolution or Dock changed: fit the stack to the new visible frame.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { PopupController.shared.relayout() }
        }
        // Layout switched while popups are open: those of the other layout close.
        layoutModeObserver = settings.$popupLayoutMode
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { _ in
                MainActor.assumeIsolated { PopupController.shared.closePopupsOfOtherLayout() }
            }
        // Default position left/right changed: open miniatures move to the new side at once.
        positionObserver = settings.$defaultPosition
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { _ in
                MainActor.assumeIsolated { PopupController.shared.miniatures.relayout() }
            }
    }

    /// Entry point for triggers (Protect events, relay webhooks). The event is recorded for the
    /// menu panel even when muted; then global mute, the camera's own mute and Focus are honored.
    func show(event: TriggerEvent) {
        let mapping = mapping(for: event)
        if let mapping {
            EventLog.shared.record(
                mapping: mapping,
                kindLabel: Self.kindLabel(for: event, mapping: mapping),
                date: event.timestamp
            )
        }

        if settings.isMuted {
            NSLog("Popups muted; skipping popup.")
            return
        }

        if let mapping, settings.isMuted(entryId: mapping.entryId) {
            NSLog("Camera muted; skipping popup.")
            return
        }

        if settings.disableDuringDND, DoNotDisturbChecker.isActive {
            NSLog("Do Not Disturb active; skipping popup.")
            return
        }

        present(event: event, isTrigger: true)
    }

    /// Buttons shown in this camera's popup: the webhook part always, a sound only on a camera
    /// with speaker and while the announcement exists.
    static func popupActions(of mapping: WebhookMapping) -> [CameraAction] {
        let canPlaySound = TalkbackService.shared.canTalk(mapping)
        return mapping.actions.filter { action in
            action.isConfigured && ActionAvailability.isShown(
                hasWebhook: action.requestURL != nil,
                hasSound: action.soundId.flatMap(SoundStore.shared.settings.announcement(id:)) != nil,
                canPlaySound: canPlaySound
            )
        }
    }

    /// Event kind for the popup chip and the menu panel ("Klingel"); nil for webhook and manual popups.
    /// Camera sound switch in the popup: Protect cameras by their microphone; webhook-only or not
    /// (yet) known cameras get it too, their stream may carry sound.
    static func mayHaveMicrophone(_ mapping: WebhookMapping) -> Bool {
        guard SettingsStore.shared.isProtectConfigured, let cameraId = mapping.protectCameraId,
              let camera = ProtectSession.shared.cameras.first(where: { $0.id == cameraId }) else { return true }
        return camera.hasMic
    }

    static func kindLabel(for event: TriggerEvent, mapping: WebhookMapping) -> String? {
        TriggerKind.displayOrder.first { event.kinds.contains($0) && mapping.triggers.contains($0) }?.label
    }

    private func mapping(for event: TriggerEvent) -> WebhookMapping? {
        event.mappingId.flatMap(settings.mapping(forEntry:)) ?? settings.mapping(for: event.webhookId)
    }

    private func present(event: TriggerEvent, isTrigger: Bool) {
        guard let mapping = mapping(for: event) else {
            NSLog("No mapping for event: \(event.webhookId) \(String(describing: event.mappingId))")
            return
        }

        // The same camera triggering again only restarts its auto-close timer.
        // The popup keeps its place in the stack so windows never jump around.
        if extendExistingPopup(for: mapping.entryId) { return }

        Task { @MainActor in
            guard let streamURL = await ProtectSession.shared.streamURL(for: mapping) else {
                NSLog("No stream URL for \(mapping.label)")
                return
            }
            // Another trigger for this entry may have opened it while the URL resolved.
            if extendExistingPopup(for: mapping.entryId) { return }

            // Without the "show all" option a new camera replaces the current popup – except one
            // that is talking or playing an announcement: it stays, the new one joins the stack.
            if !settings.showAllActiveCameras {
                dismiss(keepingBusy: true)
            }

            let screen = WindowPositioner.targetScreen(for: settings.screenTarget)
            let size = mapping.popupSize(on: screen, margin: CGFloat(settings.edgeMargin))
            let miniature = settings.popupLayoutMode == .miniature
            let popupId = UUID()
            let window = makeAlarmWindow(
                event: event, mapping: mapping, streamURL: streamURL, size: size,
                popupId: popupId, miniature: miniature
            )
            let popup = ActivePopup(
                id: popupId,
                entryId: mapping.entryId,
                window: window,
                size: size,
                position: mapping.positionOverride ?? settings.defaultPosition,
                isMiniature: miniature
            )
            activePopups.append(popup)

            if miniature {
                // Slides in at the bottom of the column, ordered front without stealing focus.
                // Hotkey and test come in at once (spinner until the stream runs); a trigger
                // waits for its first picture.
                miniatures.add(id: popup.id, window: window, fullSize: size, slidesInAtOnce: !isTrigger)
            } else {
                relayout()
                // Show without stealing focus so the user can keep typing in other apps.
                window.orderFrontRegardless()
            }
            window.startPlayback()
            if isTrigger, mapping.chimeOnOpen {
                NSSound(named: "Glass")?.play()
            }
        }
    }

    private func extendExistingPopup(for entryId: UUID) -> Bool {
        // A miniature sliding out is gone already: the camera gets a new one.
        guard let existing = activePopups.first(where: { $0.entryId == entryId && !miniatures.isLeaving($0.id) }) else {
            return false
        }
        existing.window.extendAutoClose(seconds: settings.autoCloseTimeout)
        return true
    }

    private func makeAlarmWindow(
        event: TriggerEvent,
        mapping: WebhookMapping,
        streamURL: String,
        size: CGSize,
        popupId: UUID,
        miniature: Bool
    ) -> PopupWindow {
        let entryId = mapping.entryId
        let cameraName = CamerasTab.displayName(mapping)
        let overlay = PopupOverlayContent(
            chip: mapping.showNameAndTime
                ? { [kind = Self.kindLabel(for: event, mapping: mapping)] now in
                    DisplayText.popupChip(kind: kind, camera: cameraName, date: now, seconds: true)
                }
                : nil,
            cameraName: cameraName,
            muteOptions: settings.muteOptions,
            onMute: { [weak self] duration in
                self?.settings.mute(entryId: entryId, for: duration)
            },
            talk: TalkbackService.shared.canTalk(mapping) ? PopupTalkContent(entryId: entryId) : nil,
            sound: Self.mayHaveMicrophone(mapping)
                ? PopupSoundContent(enabled: mapping.soundEnabled) { [weak self] enabled in
                    self?.settings.setSoundEnabled(enabled, for: entryId)
                }
                : nil,
            onOpenSettings: { AppActions.openCameraSettings(entryId) }
        )
        return PopupWindow(
            frame: NSRect(origin: .zero, size: size),
            streamURL: streamURL,
            soundEnabled: mapping.soundEnabled,
            rememberZoom: mapping.rememberZoom,
            initialZoom: mapping.rememberZoom ? mapping.savedZoom : nil,
            cropRegion: mapping.crop,
            thumbnailDataURI: event.thumbnail,
            autoCloseSeconds: settings.autoCloseTimeout,
            actions: Self.popupActions(of: mapping),
            overlay: overlay,
            snapshotSource: mapping.protectCameraId.map { cameraId in
                { await ProtectSession.shared.snapshot(cameraId: cameraId, maxAge: 0) }
            },
            onWillClose: { [weak self] scale, panOffset in
                self?.settings.saveZoom(for: entryId, scale: scale, panOffset: panOffset)
            },
            miniature: miniature
        ) { [weak self] in
            self?.removePopup(id: popupId)
        }
    }

    /// Lays out every active popup (`PopupStackLayout`): all stay fully visible – with more popups
    /// than room they shrink together, after a close they grow back towards their own size.
    /// With "show all" the stack sits at the default position, otherwise the single popup at its own.
    /// Size changes animate 300 ms ease-in-ease-out, without animation under "Bewegung reduzieren".
    private func relayout() {
        // Layout "Miniatur": its own column (docs/design/popup-miniatur.md).
        miniatures.relayout()
        let popups = activePopups.filter { !$0.fixedSize && !$0.isMiniature }
        guard !popups.isEmpty else { return }

        let screen = WindowPositioner.targetScreen(for: settings.screenTarget)
        let margin = CGFloat(settings.edgeMargin)
        // Re-read the settings: a changed size or a learned aspect ratio applies on the next layout.
        let sizes = popups.map { popup in
            settings.mapping(forEntry: popup.entryId)?.popupSize(on: screen, margin: margin) ?? popup.size
        }
        let position = settings.showAllActiveCameras ? settings.defaultPosition : popups[0].position
        let frames = PopupStackLayout.frames(
            sizes: sizes,
            anchor: position.anchor,
            visible: screen.visibleFrame,
            margin: margin
        )
        let animate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        for (popup, frame) in zip(popups, frames) {
            let window = popup.window
            // Already there or already gliding there: leave the running animation alone.
            if targetFrames[popup.id] == frame { continue }
            targetFrames[popup.id] = frame
            // A popup not on screen yet appears in place; the others glide.
            guard animate, window.isVisible, window.frame != frame else {
                window.setFrame(frame, display: true)
                continue
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(frame, display: true)
            }
        }
    }

    private func removePopup(id: UUID) {
        activePopups.removeAll { $0.id == id }
        targetFrames[id] = nil
        if miniatures.contains(id) {
            // The other miniatures close up (unless one is hovered right now).
            miniatures.remove(id)
        } else {
            relayout()
        }
    }

    /// Settings › Popup-Layout changed: popups opened in the other layout close (miniatures at once).
    private func closePopupsOfOtherLayout() {
        let miniature = settings.popupLayoutMode == .miniature
        let closing = activePopups.filter { !$0.fixedSize && $0.isMiniature != miniature }
        guard !closing.isEmpty else { return }
        let ids = Set(closing.map(\.id))
        activePopups.removeAll { ids.contains($0.id) }
        for popup in closing {
            popup.window.closeInterceptor = nil
            popup.window.finishClose()
        }
    }

    /// Layout "Miniatur": side, screen and the current full size of every miniature.
    private func miniatureEnvironment() -> MiniatureStackPresenter.Environment {
        let screen = WindowPositioner.targetScreen(for: settings.screenTarget)
        let margin = CGFloat(settings.edgeMargin)
        let live = activePopups.filter { $0.isMiniature && !miniatures.isLeaving($0.id) }
        // Re-read like the sizes: a changed default position applies to open miniatures too.
        let ownPosition = live.first.map { popup in
            settings.mapping(forEntry: popup.entryId).map { $0.positionOverride ?? settings.defaultPosition } ?? popup.position
        }
        let position = settings.showAllActiveCameras ? settings.defaultPosition : (ownPosition ?? settings.defaultPosition)
        let popups = activePopups
        let settings = settings
        return MiniatureStackPresenter.Environment(
            side: position.side,
            visible: screen.visibleFrame,
            screenFrame: screen.frame,
            margin: margin,
            fullSize: { id in
                guard let popup = popups.first(where: { $0.id == id }) else { return nil }
                return settings.mapping(forEntry: popup.entryId)?.popupSize(on: screen, margin: margin) ?? popup.size
            }
        )
    }

    func showTestPopup(for mapping: WebhookMapping) {
        showManualPopup(for: mapping, alarmNameFallback: "Test")
    }

    func showCropSelection(for mapping: WebhookMapping) {
        Task { @MainActor in
            guard let streamURL = await ProtectSession.shared.streamURL(for: mapping) else {
                NSLog("Stream URL required to set crop.")
                return
            }
            openCropSelection(for: mapping, streamURL: streamURL)
        }
    }

    private func openCropSelection(for mapping: WebhookMapping, streamURL: String) {
        // Crop selection is a focused editing mode, so clear any open popups.
        dismiss()

        let position = mapping.positionOverride ?? settings.defaultPosition
        let screen = WindowPositioner.targetScreen(for: settings.screenTarget)
        let margin = CGFloat(settings.edgeMargin)
        // The popup's real size (automatic or typed); the crop is measured against it.
        let size = mapping.popupSize(on: screen, margin: margin)
        let frame = PopupStackLayout.frames(
            sizes: [size],
            anchor: position.anchor,
            visible: screen.visibleFrame,
            margin: margin
        )[0]

        let entryId = mapping.entryId
        let popupId = UUID()
        let originalWidth = Double(frame.width)
        let originalHeight = Double(frame.height)

        let window = PopupWindow(
            frame: frame,
            streamURL: streamURL,
            soundEnabled: false,
            thumbnailDataURI: nil,
            autoCloseSeconds: 0,
            cropSelectionMode: true,
            onCropSave: { [weak self] normalized, pixelSize in
                self?.settings.saveCrop(
                    for: entryId,
                    crop: normalized,
                    pixelWidth: Double(pixelSize.width),
                    pixelHeight: Double(pixelSize.height),
                    originalWidth: originalWidth,
                    originalHeight: originalHeight
                )
            },
            onCropCancel: nil
        ) { [weak self] in
            self?.removePopup(id: popupId)
        }

        activePopups.append(
            ActivePopup(
                id: popupId,
                entryId: entryId,
                window: window,
                size: frame.size,
                position: position,
                fixedSize: true
            )
        )
        window.orderFrontRegardless()
        window.startPlayback()
    }

    func showHotkeyPopup(for mapping: WebhookMapping) {
        showManualPopup(for: mapping, alarmNameFallback: "Hotkey")
    }

    /// Works for every entry, including Protect-only ones without a webhook slug.
    private func showManualPopup(for mapping: WebhookMapping, alarmNameFallback: String) {
        let alarmName = mapping.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let event = TriggerEvent(
            webhookId: mapping.webhookId,
            thumbnail: nil,
            alarmName: alarmName.isEmpty ? alarmNameFallback : alarmName,
            timestamp: Date(),
            mappingId: mapping.entryId
        )
        // Manual popups bypass mute / Do Not Disturb so they always appear.
        present(event: event, isTrigger: false)
    }

    func dismiss() {
        dismiss(keepingBusy: false)
    }

    /// `keepingBusy`: popups that talk or play an announcement stay open. Miniatures slide out.
    private func dismiss(keepingBusy: Bool) {
        let closing = activePopups.filter { (!keepingBusy || !$0.window.isBusy) && !miniatures.isLeaving($0.id) }
        guard !closing.isEmpty else { return }
        let closingIds = Set(closing.map(\.id))
        activePopups.removeAll { closingIds.contains($0.id) }
        for popup in closing {
            popup.window.closePopup()
        }
    }
}

extension WebhookMapping {
    /// Width / height for the automatic size: the crop's, else the camera picture's (once seen),
    /// else nil (16:9).
    @MainActor
    var popupAspectRatio: Double? {
        if crop != nil, width > 0, height > 0 { return width / height }
        return protectCameraId.flatMap(ProtectSession.shared.aspectRatio(cameraId:))
    }

    /// The size this camera's popup asks for on `screen` (before the stack shrinks it).
    @MainActor
    func popupSize(on screen: NSScreen, margin: CGFloat) -> CGSize {
        PopupSizing.size(override: sizeOverride, aspect: popupAspectRatio, visible: screen.visibleFrame.size, margin: margin)
    }
}
