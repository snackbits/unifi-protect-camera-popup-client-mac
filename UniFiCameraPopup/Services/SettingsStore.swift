import Combine
import Foundation
import ServiceManagement

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var serverURL: String {
        didSet { persist() }
    }

    @Published var appToken: String {
        didSet { persist() }
    }

    @Published var mappings: [WebhookMapping] {
        didSet { persist() }
    }

    @Published var defaultPosition: PopupPosition {
        didSet { persist() }
    }

    @Published var edgeMargin: Double {
        didSet { persist() }
    }

    @Published var autoCloseTimeout: Double {
        didSet { persist() }
    }

    @Published var screenTarget: ScreenTarget {
        didSet { persist() }
    }

    @Published var multiAlarmBehavior: MultiAlarmBehavior {
        didSet { persist() }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            LaunchAtLoginHelper.setEnabled(launchAtLogin)
            persist()
        }
    }

    private let defaults = UserDefaults.standard
    private let storageKey = "unifi.camera.popup.settings"

    private struct PersistedSettings: Codable {
        var serverURL: String
        var appToken: String
        var mappings: [WebhookMapping]
        var defaultPosition: PopupPosition
        var defaultWidth: Double?
        var defaultHeight: Double?
        var edgeMargin: Double
        var autoCloseTimeout: Double
        var screenTarget: ScreenTarget
        var multiAlarmBehavior: MultiAlarmBehavior
        var launchAtLogin: Bool
    }

    private init() {
        if let data = defaults.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode(PersistedSettings.self, from: data) {
            serverURL = saved.serverURL
            appToken = saved.appToken
            mappings = Self.migrateMappingDimensions(
                mappings: saved.mappings,
                from: data,
                defaultWidth: saved.defaultWidth ?? 480,
                defaultHeight: saved.defaultHeight ?? 270
            )
            defaultPosition = saved.defaultPosition
            edgeMargin = saved.edgeMargin
            autoCloseTimeout = saved.autoCloseTimeout
            screenTarget = saved.screenTarget
            multiAlarmBehavior = saved.multiAlarmBehavior
            launchAtLogin = saved.launchAtLogin
        } else {
            serverURL = "wss://your-domain.example/ws"
            appToken = ""
            mappings = []
            defaultPosition = .topRight
            edgeMargin = 16
            autoCloseTimeout = 30
            screenTarget = .main
            multiAlarmBehavior = .replace
            launchAtLogin = LaunchAtLoginHelper.isEnabled
        }
    }

    func mapping(for webhookId: String) -> WebhookMapping? {
        mappings.first { $0.webhookId == webhookId }
    }

    func addMapping() {
        mappings.append(WebhookMapping())
    }

    func removeMapping(id: UUID) {
        mappings.removeAll { $0.entryId == id }
    }

    private static func migrateMappingDimensions(
        mappings: [WebhookMapping],
        from data: Data,
        defaultWidth: Double,
        defaultHeight: Double
    ) -> [WebhookMapping] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let mappingJSON = json["mappings"] as? [[String: Any]],
              mappingJSON.count == mappings.count else {
            return mappings
        }

        return zip(mappings, mappingJSON).map { mapping, dict in
            var migrated = mapping
            let hadWidth = dict["width"] != nil
                || (dict["widthOverride"] != nil && !(dict["widthOverride"] is NSNull))
            let hadHeight = dict["height"] != nil
                || (dict["heightOverride"] != nil && !(dict["heightOverride"] is NSNull))

            if !hadWidth {
                migrated.width = defaultWidth
            }
            if !hadHeight {
                migrated.height = defaultHeight
            }
            return migrated
        }
    }

    private func persist() {
        let payload = PersistedSettings(
            serverURL: serverURL,
            appToken: appToken,
            mappings: mappings,
            defaultPosition: defaultPosition,
            defaultWidth: nil,
            defaultHeight: nil,
            edgeMargin: edgeMargin,
            autoCloseTimeout: autoCloseTimeout,
            screenTarget: screenTarget,
            multiAlarmBehavior: multiAlarmBehavior,
            launchAtLogin: launchAtLogin
        )

        if let data = try? JSONEncoder().encode(payload) {
            defaults.set(data, forKey: storageKey)
        }
    }
}

enum LaunchAtLoginHelper {
    private static let serviceIdentifier = "com.snackbits.UniFiCameraPopup.LoginItem"

    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    static func setEnabled(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Launch at login error: \(error.localizedDescription)")
        }
    }
}
