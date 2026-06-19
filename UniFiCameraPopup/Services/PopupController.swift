import AppKit

@MainActor
final class PopupController {
    static let shared = PopupController()

    /// A popup that is currently on screen. The order of `activePopups` is the
    /// stacking order and is kept stable: a re-triggering camera only restarts
    /// its timeout, it is never moved within the stack.
    private struct ActivePopup {
        let webhookId: String
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
        guard let mapping = settings.mapping(for: event.webhookId) else {
            NSLog("No mapping for webhook id: \(event.webhookId)")
            return
        }

        let streamURL = mapping.rtspsURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !streamURL.isEmpty else { return }

        // The same camera triggering again only restarts its auto-close timer.
        // The popup keeps its place in the stack so windows never jump around.
        if let existing = activePopups.first(where: { $0.webhookId == event.webhookId }) {
            existing.window.extendAutoClose(seconds: settings.autoCloseTimeout)
            return
        }

        // Without the "show all" option a new camera replaces the current popup.
        if !settings.showAllActiveCameras {
            dismiss()
        }

        let window = makeAlarmWindow(event: event, mapping: mapping, streamURL: streamURL)
        activePopups.append(
            ActivePopup(
                webhookId: event.webhookId,
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

    private func makeAlarmWindow(
        event: TriggerEvent,
        mapping: WebhookMapping,
        streamURL: String
    ) -> PopupWindow {
        let webhookId = event.webhookId
        return PopupWindow(
            frame: NSRect(x: 0, y: 0, width: CGFloat(mapping.width), height: CGFloat(mapping.height)),
            streamURL: streamURL,
            soundEnabled: mapping.soundEnabled,
            rememberZoom: mapping.rememberZoom,
            initialZoom: mapping.rememberZoom ? mapping.savedZoom : nil,
            cropRegion: mapping.crop,
            thumbnailDataURI: event.thumbnail,
            autoCloseSeconds: settings.autoCloseTimeout,
            onWillClose: { [weak self] scale, panOffset in
                self?.settings.saveZoom(for: webhookId, scale: scale, panOffset: panOffset)
            }
        ) { [weak self] in
            self?.removePopup(webhookId: webhookId)
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

    private func removePopup(webhookId: String) {
        activePopups.removeAll { $0.webhookId == webhookId }
        relayout()
    }

    func showTestPopup(for mapping: WebhookMapping) {
        showManualPopup(for: mapping, alarmNameFallback: "Test")
    }

    func showCropSelection(for mapping: WebhookMapping) {
        let streamURL = mapping.rtspsURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !streamURL.isEmpty else {
            NSLog("RTSP URL required to set crop.")
            return
        }

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
        let webhookId = mapping.webhookId
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
            self?.removePopup(webhookId: webhookId)
        }

        activePopups.append(
            ActivePopup(
                webhookId: webhookId,
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

    private func showManualPopup(for mapping: WebhookMapping, alarmNameFallback: String) {
        let webhookId = mapping.webhookId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !webhookId.isEmpty else {
            NSLog("Webhook slug required to open popup.")
            return
        }

        let streamURL = mapping.rtspsURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !streamURL.isEmpty else {
            NSLog("RTSP URL required to open popup.")
            return
        }

        let alarmName = mapping.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let event = TriggerEvent(
            webhookId: webhookId,
            thumbnail: nil,
            alarmName: alarmName.isEmpty ? alarmNameFallback : alarmName,
            timestamp: Date()
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
