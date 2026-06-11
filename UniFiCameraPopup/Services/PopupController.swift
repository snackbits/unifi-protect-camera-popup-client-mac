import AppKit

@MainActor
final class PopupController {
    static let shared = PopupController()

    private var currentWindow: PopupWindow?
    private var currentWebhookId: String?
    private let settings = SettingsStore.shared

    private init() {}

    func show(event: TriggerEvent) {
        guard let mapping = settings.mapping(for: event.webhookId) else {
            NSLog("No mapping for webhook id: \(event.webhookId)")
            return
        }

        let streamURL = mapping.rtspsURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !streamURL.isEmpty else { return }

        if let currentWindow,
           currentWebhookId == event.webhookId,
           settings.multiAlarmBehavior == .extend {
            currentWindow.extendAutoClose(seconds: settings.autoCloseTimeout)
            return
        }

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

        let window = PopupWindow(
            frame: frame,
            streamURL: streamURL,
            thumbnailDataURI: event.thumbnail,
            autoCloseSeconds: settings.autoCloseTimeout
        ) { [weak self] in
            self?.currentWindow = nil
            self?.currentWebhookId = nil
        }

        currentWindow = window
        currentWebhookId = event.webhookId
        // Show without stealing focus so the user can keep typing in other apps.
        window.orderFrontRegardless()
        window.startPlayback()
    }

    func showTestPopup(for mapping: WebhookMapping) {
        let webhookId = mapping.webhookId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !webhookId.isEmpty else {
            NSLog("Webhook slug required to test popup.")
            return
        }

        let streamURL = mapping.rtspsURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !streamURL.isEmpty else {
            NSLog("RTSP URL required to test popup.")
            return
        }

        let alarmName = mapping.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let testEvent = TriggerEvent(
            webhookId: webhookId,
            thumbnail: nil,
            alarmName: alarmName.isEmpty ? "Test" : alarmName,
            timestamp: Date()
        )
        show(event: testEvent)
    }

    func dismiss() {
        currentWindow?.closePopup()
        currentWindow = nil
        currentWebhookId = nil
    }
}
