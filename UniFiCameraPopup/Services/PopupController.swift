import AppKit

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
    }

    private var activePopups: [ActivePopup] = []
    private let settings = SettingsStore.shared

    private init() {}

    func show(event: TriggerEvent) {
        if settings.isMuted {
            NSLog("Popups muted; skipping popup.")
            return
        }

        if settings.disableDuringDND, DoNotDisturbChecker.isActive {
            NSLog("Do Not Disturb active; skipping popup.")
            return
        }

        present(event: event)
    }

    private func present(event: TriggerEvent) {
        let found = event.mappingId.flatMap(settings.mapping(forEntry:)) ?? settings.mapping(for: event.webhookId)
        guard let mapping = found else {
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

            let window = makeAlarmWindow(event: event, mapping: mapping, streamURL: streamURL)
            activePopups.append(
                ActivePopup(
                    entryId: mapping.entryId,
                    window: window,
                    size: CGSize(width: CGFloat(mapping.width), height: CGFloat(mapping.height)),
                    position: mapping.positionOverride ?? settings.defaultPosition
                )
            )

            relayout()
            // Show without stealing focus so the user can keep typing in other apps.
            window.orderFrontRegardless()
            window.startPlayback()
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
        streamURL: String
    ) -> PopupWindow {
        let entryId = mapping.entryId
        return PopupWindow(
            frame: NSRect(x: 0, y: 0, width: CGFloat(mapping.width), height: CGFloat(mapping.height)),
            streamURL: streamURL,
            soundEnabled: mapping.soundEnabled,
            rememberZoom: mapping.rememberZoom,
            initialZoom: mapping.rememberZoom ? mapping.savedZoom : nil,
            cropRegion: mapping.crop,
            thumbnailDataURI: event.thumbnail,
            autoCloseSeconds: settings.autoCloseTimeout,
            actions: mapping.actions.filter(\.isConfigured),
            onWillClose: { [weak self] scale, panOffset in
                self?.settings.saveZoom(for: entryId, scale: scale, panOffset: panOffset)
            }
        ) { [weak self] in
            self?.removePopup(entryId: entryId)
        }
    }

    /// Repositions every active popup. With "show all" enabled the popups are
    /// stacked at the default position; otherwise the single popup uses its own
    /// (possibly overridden) position.
    private func relayout() {
        guard !activePopups.isEmpty else { return }

        let screen = WindowPositioner.targetScreen(for: settings.screenTarget)
        let margin = CGFloat(settings.edgeMargin)

        if settings.showAllActiveCameras {
            let frames = WindowPositioner.stackedFrames(
                sizes: activePopups.map(\.size),
                position: settings.defaultPosition,
                margin: margin,
                screen: screen
            )
            for (index, popup) in activePopups.enumerated() {
                popup.window.setFrame(frames[index], display: true)
            }
        } else {
            for popup in activePopups {
                let frame = WindowPositioner.frame(
                    width: popup.size.width,
                    height: popup.size.height,
                    position: popup.position,
                    margin: margin,
                    screen: screen
                )
                popup.window.setFrame(frame, display: true)
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
        let width = CGFloat(mapping.width)
        let height = CGFloat(mapping.height)
        let screen = WindowPositioner.targetScreen(for: settings.screenTarget)
        let frame = WindowPositioner.frame(
            width: width,
            height: height,
            position: position,
            margin: CGFloat(settings.edgeMargin),
            screen: screen
        )

        let entryId = mapping.entryId
        let originalWidth = mapping.width
        let originalHeight = mapping.height

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
                size: CGSize(width: width, height: height),
                position: position
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
        present(event: event)
    }

    func dismiss() {
        let popups = activePopups
        activePopups = []
        for popup in popups {
            popup.window.closePopup()
        }
    }
}
