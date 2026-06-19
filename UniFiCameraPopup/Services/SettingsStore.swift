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

    /// When enabled, every triggering camera gets its own popup, stacked beneath
    /// the previous ones. When disabled, a new camera replaces the current popup.
    @Published var showAllActiveCameras: Bool {
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

    /// When enabled, no popups are shown while a macOS Focus / Do Not Disturb
    /// mode is active.
    @Published var disableDuringDND: Bool {
        didSet { persist() }
    }

    /// When set to a future date, all popups are suppressed until then.
    @Published var muteUntil: Date? {
        didSet { persist() }
    }

    /// Whether popups are currently muted via the temporary mute buttons.
    var isMuted: Bool {
        guard let muteUntil else { return false }
        return muteUntil > Date()
    }

    func mute(for duration: TimeInterval) {
        muteUntil = Date().addingTimeInterval(duration)
    }

    func clearMute() {
        muteUntil = nil
    }

    /// Reconciles the persisted "launch at login" preference with the actual
    /// `SMAppService` registration state. Call this on app launch so a stale or
    /// failed registration repairs itself instead of silently staying broken.
    func reconcileLaunchAtLogin() {
        let resolved = LaunchAtLoginHelper.synchronize(desired: launchAtLogin)
        if resolved != launchAtLogin {
            launchAtLogin = resolved
        }
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
        var showAllActiveCameras: Bool?
        var launchAtLogin: Bool
        var autoUpdate: Bool?
        var disableDuringDND: Bool?
        var muteUntil: Date?
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
            showAllActiveCameras = saved.showAllActiveCameras ?? false
            launchAtLogin = saved.launchAtLogin
            autoUpdate = saved.autoUpdate ?? true
            disableDuringDND = saved.disableDuringDND ?? false
            muteUntil = saved.muteUntil
        } else {
            installationId = Self.makeInstallationId()
            mappings = []
            defaultPosition = .topRight
            edgeMargin = 16
            autoCloseTimeout = 30
            screenTarget = .main
            showAllActiveCameras = false
            launchAtLogin = LaunchAtLoginHelper.isEnabled
            autoUpdate = true
            disableDuringDND = false
            muteUntil = nil
        }

        persist()
    }

    func mapping(for webhookId: String) -> WebhookMapping? {
        mappings.first { $0.webhookId == webhookId }
    }

    func saveZoom(for webhookId: String, scale: CGFloat, panOffset: CGPoint) {
        guard let index = mappings.firstIndex(where: { $0.webhookId == webhookId }) else { return }
        guard mappings[index].rememberZoom else { return }

        mappings[index].savedZoom = SavedCameraZoom(
            scale: Double(scale),
            panOffsetX: Double(panOffset.x),
            panOffsetY: Double(panOffset.y)
        )
    }

    func saveCrop(
        for entryId: UUID,
        crop: CameraCrop,
        pixelWidth: Double,
        pixelHeight: Double,
        originalWidth: Double,
        originalHeight: Double
    ) {
        guard let index = mappings.firstIndex(where: { $0.entryId == entryId }) else { return }

        var savedCrop = crop
        savedCrop.originalWidth = originalWidth
        savedCrop.originalHeight = originalHeight

        mappings[index].crop = savedCrop
        mappings[index].width = max(pixelWidth, 40)
        mappings[index].height = max(pixelHeight, 40)
    }

    func removeCrop(for entryId: UUID) {
        guard let index = mappings.firstIndex(where: { $0.entryId == entryId }),
              let crop = mappings[index].crop else { return }

        mappings[index].width = crop.originalWidth
        mappings[index].height = crop.originalHeight
        mappings[index].crop = nil
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
            showAllActiveCameras: showAllActiveCameras,
            launchAtLogin: launchAtLogin,
            autoUpdate: autoUpdate,
            disableDuringDND: disableDuringDND,
            muteUntil: muteUntil
        )

        if let data = try? JSONEncoder().encode(payload) {
            defaults.set(data, forKey: storageKey)
        }
    }
}

enum LaunchAtLoginHelper {
    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    /// True when the login item is registered but the user still has to approve
    /// it in System Settings → General → Login Items. In this state the app will
    /// NOT launch at login until approved.
    static var requiresApproval: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .requiresApproval
        }
        return false
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        guard #available(macOS 13.0, *) else { return false }

        do {
            if enabled {
                // Registering an already-enabled service throws; skip in that case.
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            NSLog("Launch at login error: \(error.localizedDescription)")
            return false
        }
    }

    /// Reconciles the persisted preference with the real system registration
    /// state and returns the value the toggle should reflect afterwards.
    ///
    /// This is the self-healing step: if the preference says "on" but the system
    /// lost the registration (e.g. a previously failed `register()`, the app was
    /// moved, or the login item was reset), we re-register here.
    static func synchronize(desired: Bool) -> Bool {
        guard #available(macOS 13.0, *) else { return false }

        let status = SMAppService.mainApp.status

        if desired {
            switch status {
            case .enabled, .requiresApproval:
                // Already registered (approval is handled separately in the UI).
                return true
            default:
                setEnabled(true)
                let newStatus = SMAppService.mainApp.status
                return newStatus == .enabled || newStatus == .requiresApproval
            }
        } else {
            if status == .enabled || status == .requiresApproval {
                setEnabled(false)
            }
            return false
        }
    }

    static func openLoginItemsSettings() {
        if #available(macOS 13.0, *) {
            SMAppService.openSystemSettingsLoginItems()
        }
    }
}
