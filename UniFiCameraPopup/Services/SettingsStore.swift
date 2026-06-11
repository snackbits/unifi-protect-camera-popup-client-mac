import Combine
import Foundation
import ServiceManagement

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    /// Unique per-installation identifier used in webhook URLs so that
    /// different users never share the same webhook paths.
    @Published private(set) var installationId: String {
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

    /// When enabled, newer builds are downloaded and installed without asking.
    @Published var autoUpdate: Bool {
        didSet { persist() }
    }

    private let defaults = UserDefaults.standard
    private let storageKey = "unifi.camera.popup.settings"

    private struct PersistedSettings: Codable {
        var installationId: String?
        var mappings: [WebhookMapping]
        var defaultPosition: PopupPosition
        var defaultWidth: Double?
        var defaultHeight: Double?
        var edgeMargin: Double
        var autoCloseTimeout: Double
        var screenTarget: ScreenTarget
        var multiAlarmBehavior: MultiAlarmBehavior
        var launchAtLogin: Bool
        var autoUpdate: Bool?
    }

    private init() {
        if let data = defaults.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode(PersistedSettings.self, from: data) {
            installationId = saved.installationId?.isEmpty == false
                ? saved.installationId!
                : Self.makeInstallationId()
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
            autoUpdate = saved.autoUpdate ?? true
        } else {
            installationId = Self.makeInstallationId()
            mappings = []
            defaultPosition = .topRight
            edgeMargin = 16
            autoCloseTimeout = 30
            screenTarget = .main
            multiAlarmBehavior = .replace
            launchAtLogin = LaunchAtLoginHelper.isEnabled
            autoUpdate = true
        }

        persist()
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

    /// Generates a fresh installation ID. This changes all webhook URLs, so
    /// the user must reconfigure UniFi Protect afterwards.
    func regenerateInstallationId() {
        installationId = Self.makeInstallationId()
    }

    private static func makeInstallationId() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
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
            installationId: installationId,
            mappings: mappings,
            defaultPosition: defaultPosition,
            defaultWidth: nil,
            defaultHeight: nil,
            edgeMargin: edgeMargin,
            autoCloseTimeout: autoCloseTimeout,
            screenTarget: screenTarget,
            multiAlarmBehavior: multiAlarmBehavior,
            launchAtLogin: launchAtLogin,
            autoUpdate: autoUpdate
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
