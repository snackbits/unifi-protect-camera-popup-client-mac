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
        let width = CGFloat(mapping.widthOverride ?? settings.defaultWidth)
        let height = CGFloat(mapping.heightOverride ?? settings.defaultHeight)
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
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showTestPopup() {
        let testEvent = TriggerEvent(
            webhookId: settings.mappings.first?.webhookId ?? "test",
            thumbnail: nil,
            alarmName: "Test",
            timestamp: Date()
        )

        if settings.mappings.first != nil {
            show(event: testEvent)
        } else {
            NSLog("Add at least one webhook mapping to test the popup.")
        }
    }

    func dismiss() {
        currentWindow?.closePopup()
        currentWindow = nil
        currentWebhookId = nil
    }
}
