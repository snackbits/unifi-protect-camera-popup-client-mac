import Foundation

struct WebhookMapping: Codable, Identifiable, Equatable {
    var id: String { webhookId }
    var webhookId: String
    var rtspsURL: String
    var label: String
    var positionOverride: PopupPosition?
    var widthOverride: Double?
    var heightOverride: Double?

    init(
        webhookId: String = "",
        rtspsURL: String = "",
        label: String = "",
        positionOverride: PopupPosition? = nil,
        widthOverride: Double? = nil,
        heightOverride: Double? = nil
    ) {
        self.webhookId = webhookId
        self.rtspsURL = rtspsURL
        self.label = label
        self.positionOverride = positionOverride
        self.widthOverride = widthOverride
        self.heightOverride = heightOverride
    }
}

struct TriggerEvent: Equatable {
    let webhookId: String
    let thumbnail: String?
    let alarmName: String?
    let timestamp: Date
}
