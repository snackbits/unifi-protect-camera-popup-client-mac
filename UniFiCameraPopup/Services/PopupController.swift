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
    private let settings = SettingsStore.shared

    private init() {}

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

            // Without the "show all" option a new camera replaces the current popup.
            if !settings.showAllActiveCameras {
                dismiss()
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
            chipText: mapping.showNameAndTime
                ? DisplayText.popupChip(kind: Self.kindLabel(for: event, mapping: mapping), camera: cameraName, date: event.timestamp)
                : nil,
            cameraName: cameraName,
            muteOptions: settings.muteOptions,
            onMute: { [weak self] duration in
                self?.settings.mute(entryId: entryId, for: duration)
            },
            talk: TalkbackService.shared.canTalk(mapping) ? PopupTalkContent(entryId: entryId) : nil
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
            actions: mapping.actions.filter(\.isConfigured),
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
        let popups = activePopups
        activePopups = []
        for popup in popups {
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
