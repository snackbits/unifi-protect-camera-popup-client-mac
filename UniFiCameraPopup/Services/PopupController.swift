import AppCore
import AppKit
import ProtectKit

@MainActor
final class PopupController {
    static let shared = PopupController()

    /// A popup that is currently on screen. The order of `activePopups` is the
    /// stacking order and is kept stable: a re-triggering camera only restarts
    /// its timeout, it is never moved within the stack.
    private struct ActivePopup {
        /// The mapping entry shown. Protect-only entries have no webhook slug,
        /// so popups are keyed by entry, never by webhook id.
        let entryId: UUID
        let window: PopupWindow
        let size: CGSize
        /// The position used when only a single popup is shown.
        let position: PopupPosition
        /// Crop selection keeps its size; the stack never resizes it.
        var fixedSize = false
    }

    private var activePopups: [ActivePopup] = []
    /// Frame each popup was last sent to (animation target). An unchanged target never restarts
    /// a running 300 ms animation.
    private var targetFrames: [UUID: NSRect] = [:]
    private let settings = SettingsStore.shared
    private var screenObserver: NSObjectProtocol?

    private init() {
        // Display added/removed, resolution or Dock changed: fit the stack to the new visible frame.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { PopupController.shared.relayout() }
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
            let window = makeAlarmWindow(event: event, mapping: mapping, streamURL: streamURL, size: size)
            activePopups.append(
                ActivePopup(
                    entryId: mapping.entryId,
                    window: window,
                    size: size,
                    position: mapping.positionOverride ?? settings.defaultPosition
                )
            )

            relayout()
            // Show without stealing focus so the user can keep typing in other apps.
            window.orderFrontRegardless()
            window.startPlayback()
            if isTrigger, mapping.chimeOnOpen {
                NSSound(named: "Glass")?.play()
            }
        }
    }

    private func extendExistingPopup(for entryId: UUID) -> Bool {
        guard let existing = activePopups.first(where: { $0.entryId == entryId }) else { return false }
        existing.window.extendAutoClose(seconds: settings.autoCloseTimeout)
        return true
    }

    private func makeAlarmWindow(
        event: TriggerEvent,
        mapping: WebhookMapping,
        streamURL: String,
        size: CGSize
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
            onWillClose: { [weak self] scale, panOffset in
                self?.settings.saveZoom(for: entryId, scale: scale, panOffset: panOffset)
            }
        ) { [weak self] in
            self?.removePopup(entryId: entryId)
        }
    }

    /// Lays out every active popup (`PopupStackLayout`): all stay fully visible – with more popups
    /// than room they shrink together, after a close they grow back towards their own size.
    /// With "show all" the stack sits at the default position, otherwise the single popup at its own.
    /// Size changes animate 300 ms ease-in-ease-out, without animation under "Bewegung reduzieren".
    private func relayout() {
        let popups = activePopups.filter { !$0.fixedSize }
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
            if targetFrames[popup.entryId] == frame { continue }
            targetFrames[popup.entryId] = frame
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

    private func removePopup(entryId: UUID) {
        activePopups.removeAll { $0.entryId == entryId }
        targetFrames[entryId] = nil
        relayout()
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
            self?.removePopup(entryId: entryId)
        }

        activePopups.append(
            ActivePopup(
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

    /// `keepingBusy`: popups that talk or play an announcement stay open.
    private func dismiss(keepingBusy: Bool) {
        let closing = activePopups.filter { !keepingBusy || !$0.window.isBusy }
        guard !closing.isEmpty else { return }
        let closingIds = Set(closing.map(\.entryId))
        activePopups.removeAll { closingIds.contains($0.entryId) }
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
