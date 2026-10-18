import AppCore
import Combine
import Foundation
import ProtectKit
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

    @Published var protectHost: String {
        didSet {
            // A certificate pin never carries over to another console.
            if Self.normalizedHost(oldValue) != Self.normalizedHost(protectHost) {
                protectCertificateFingerprint = nil
                protectConsoleName = nil
            }
            persist()
        }
    }

    @Published var protectCertificateFingerprint: String? {
        didSet { persist() }
    }

    /// Console name from discovery ("UDM Pro"); nil for a typed address.
    @Published var protectConsoleName: String? {
        didSet { persist() }
    }

    /// Protect Integration API key. Lives only in the keychain (never in
    /// UserDefaults or configuration exports).
    var protectAPIKey: String {
        get { KeychainStore.string(service: KeychainStore.protectAPIKeyService, account: "default") ?? "" }
        set {
            if newValue.isEmpty {
                KeychainStore.delete(service: KeychainStore.protectAPIKeyService, account: "default")
            } else {
                _ = KeychainStore.set(newValue, service: KeychainStore.protectAPIKeyService, account: "default")
            }
            objectWillChange.send()
        }
    }

    /// Comparison/storage form of a console address (see `ProtectClient.canonicalHost`).
    /// Unparseable input falls back to its trimmed, lowercased spelling.
    static func normalizedHost(_ host: String) -> String {
        ProtectClient.canonicalHost(host) ?? host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var isProtectConfigured: Bool {
        !protectHost.trimmingCharacters(in: .whitespaces).isEmpty && !protectAPIKey.isEmpty
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

    /// Global and per-camera mutes. Absolute dates: a mute survives a restart.
    @Published private(set) var muteSchedule: MuteSchedule {
        didSet { persist() }
    }

    /// The two offered mute lengths ("Kurz" / "Lang").
    @Published var muteShort: MuteDuration {
        didSet { persist() }
    }

    @Published var muteLong: MuteDuration {
        didSet { persist() }
    }

    var muteOptions: [MuteDuration] { [muteShort, muteLong] }

    /// "Erscheinungsbild": applied to `NSApp.appearance` by `AppDelegate`.
    @Published var appearance: AppearanceMode {
        didSet { persist() }
    }

    /// Whether all popups are muted right now (menu bar badge, global check).
    var isMuted: Bool {
        muteSchedule.isGloballyMuted(at: Date())
    }

    /// Whether this camera must not open a popup (own mute or global mute).
    func isMuted(entryId: UUID) -> Bool {
        muteSchedule.isMuted(entry: entryId.uuidString, at: Date())
    }

    func muteAll(for duration: MuteDuration) {
        muteSchedule.muteAll(for: duration.seconds, from: Date())
    }

    func mute(entryId: UUID, for duration: MuteDuration) {
        muteSchedule.mute(entry: entryId.uuidString, for: duration.seconds, from: Date())
    }

    func clearGlobalMute() {
        muteSchedule.clearGlobal()
    }

    func clearMute(entryId: UUID) {
        muteSchedule.clear(entry: entryId.uuidString)
    }

    /// Lifts every mute (menu "Stummschaltung aufheben").
    func clearMute() {
        muteSchedule.clearAll()
    }

    /// Drops ended mutes and mutes of removed cameras; writes only on change.
    func pruneMutes() {
        var pruned = muteSchedule
        pruned.prune(at: Date(), validEntries: Set(mappings.map(\.entryId.uuidString)))
        if pruned != muteSchedule {
            muteSchedule = pruned
        }
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

    #if DEBUG
    // `--render-snapshots` runs against a throwaway suite so nothing reaches the real settings.
    private let defaults = SnapshotRenderer.isActive ? SnapshotRenderer.isolatedDefaults : UserDefaults.standard
    #else
    private let defaults = UserDefaults.standard
    #endif
    private let storageKey = "unifi.camera.popup.settings"
    /// Phase-2 state under a key of its own: the installed older build rewrites `storageKey`
    /// without the keys it does not know (see `SettingsExtensions`).
    private let extensionsKey = "settingsExtensionsV2"
    /// Where raw, undecodable settings are preserved instead of being overwritten.
    private static let backupKey = "unifi.camera.popup.settings.corrupted-backup"

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
        var protectHost: String?
        var protectCertificateFingerprint: String?
        var muteSchedule: MuteSchedule?
        var muteShort: MuteDuration?
        var muteLong: MuteDuration?
        var appearance: AppearanceMode?
        var protectConsoleName: String?
    }

    private init() {
        let existingData = defaults.data(forKey: storageKey)

        if let data = existingData,
           let saved = try? JSONDecoder().decode(PersistedSettings.self, from: data) {
            installationId = saved.installationId?.isEmpty == false
                ? saved.installationId!
                : Self.makeInstallationId()
            let loaded = Self.loadActionTokens(into: Self.migrateMappingDimensions(
                mappings: saved.mappings,
                from: data,
                defaultWidth: saved.defaultWidth ?? 480,
                defaultHeight: saved.defaultHeight ?? 270
            ))
            mappings = loaded.mappings
            keychainTokens = loaded.fromKeychain
            defaultPosition = saved.defaultPosition
            edgeMargin = saved.edgeMargin
            autoCloseTimeout = saved.autoCloseTimeout
            screenTarget = saved.screenTarget
            showAllActiveCameras = saved.showAllActiveCameras ?? false
            launchAtLogin = saved.launchAtLogin
            autoUpdate = saved.autoUpdate ?? true
            disableDuringDND = saved.disableDuringDND ?? false
            // The extension holds what an older build rewriting the main blob would have dropped.
            let ext = SettingsExtensions.decode(defaults.data(forKey: extensionsKey))
            var schedule = MuteSchedule.migrated(
                stored: ext?.muteSchedule ?? saved.muteSchedule,
                legacyGlobalUntil: saved.muteUntil
            )
            schedule.prune(at: Date(), validEntries: Set(loaded.mappings.map(\.entryId.uuidString)))
            muteSchedule = schedule
            muteShort = ext?.muteShort ?? saved.muteShort ?? .defaultShort
            muteLong = ext?.muteLong ?? saved.muteLong ?? .defaultLong
            appearance = ext?.appearance ?? saved.appearance ?? .system
            protectConsoleName = ext?.protectConsoleName ?? saved.protectConsoleName
            protectHost = (ext?.protectHost ?? saved.protectHost).map { ProtectClient.canonicalHost($0) ?? $0 } ?? ""
            protectCertificateFingerprint = ext?.protectCertificateFingerprint ?? saved.protectCertificateFingerprint
            if let ext {
                mappings = Self.overlay(ext, onto: mappings)
            }

            // Decode succeeded: rewrite the (possibly migrated/normalized) payload.
            persist()
        } else {
            if let data = existingData {
                // Settings existed but could not be decoded (e.g. an update
                // changed the schema in an incompatible way). Do NOT overwrite
                // them with defaults – preserve the raw data once as a backup so
                // a later, fixed build can still recover it, and start with
                // in-memory defaults for this launch only.
                if defaults.data(forKey: Self.backupKey) == nil {
                    defaults.set(data, forKey: Self.backupKey)
                }
                NSLog("SettingsStore: persisted settings could not be decoded; preserved raw data under \(Self.backupKey), using in-memory defaults")
            }

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
            muteSchedule = MuteSchedule()
            muteShort = .defaultShort
            muteLong = .defaultLong
            appearance = .system
            protectConsoleName = nil
            protectHost = ""
            protectCertificateFingerprint = nil

            // Only persist on a genuine first launch (no prior data). When prior
            // data existed but failed to decode, leave it untouched above.
            if existingData == nil {
                persist()
            }
        }
    }

    func mapping(for webhookId: String) -> WebhookMapping? {
        mappings.first { $0.webhookTriggerEnabled && $0.webhookId == webhookId }
    }

    func mappings(forProtectCamera cameraId: String) -> [WebhookMapping] {
        mappings.filter { $0.protectCameraId == cameraId }
    }

    func mapping(forEntry id: UUID) -> WebhookMapping? {
        mappings.first { $0.entryId == id }
    }

    func saveZoom(for entryId: UUID, scale: CGFloat, panOffset: CGPoint) {
        guard let index = mappings.firstIndex(where: { $0.entryId == entryId }) else { return }
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
        mappings.append(WebhookMapping(webhookTriggerEnabled: true))
    }

    func removeMapping(id: UUID) {
        mappings.removeAll { $0.entryId == id }
        muteSchedule.clear(entry: id.uuidString)
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

    private func currentPersistedSettings() -> PersistedSettings {
        PersistedSettings(
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
            // Still written so an older installed build keeps honoring a global mute.
            muteUntil: muteSchedule.globalUntil,
            protectHost: protectHost,
            protectCertificateFingerprint: protectCertificateFingerprint,
            muteSchedule: muteSchedule,
            muteShort: muteShort,
            muteLong: muteLong,
            appearance: appearance,
            protectConsoleName: protectConsoleName
        )
    }

    /// Applies extension values to the mappings decoded from the main blob. The extension wins for
    /// fields an older build cannot write; ids that no longer exist are ignored.
    private static func overlay(_ ext: SettingsExtensions, onto mappings: [WebhookMapping]) -> [WebhookMapping] {
        mappings.map { mapping in
            var mapping = mapping
            if let m = ext.mappings[mapping.entryId.uuidString] {
                if let id = m.protectCameraId { mapping.protectCameraId = id }
                if let raw = m.triggers { mapping.triggers = Set(raw.compactMap(TriggerKind.init(rawValue:))) }
                if let enabled = m.webhookTriggerEnabled { mapping.webhookTriggerEnabled = enabled }
                if let chime = m.chimeOnOpen { mapping.chimeOnOpen = chime }
            }
            mapping.actions = mapping.actions.map { action in
                var action = action
                if let a = ext.actions[action.id.uuidString] {
                    if let icon = a.icon.flatMap(ActionIcon.init(rawValue:)) { action.icon = icon }
                    if let confirm = a.confirmBeforeRun { action.confirmBeforeRun = confirm }
                }
                return action
            }
            return mapping
        }
    }

    private func currentExtensions() -> SettingsExtensions {
        var mappingValues: [String: SettingsExtensions.Mapping] = [:]
        var actionValues: [String: SettingsExtensions.Action] = [:]
        for mapping in mappings {
            mappingValues[mapping.entryId.uuidString] = .init(
                protectCameraId: mapping.protectCameraId,
                triggers: TriggerKind.ordered.filter(mapping.triggers.contains).map(\.rawValue),
                webhookTriggerEnabled: mapping.webhookTriggerEnabled,
                chimeOnOpen: mapping.chimeOnOpen
            )
            for action in mapping.actions {
                actionValues[action.id.uuidString] = .init(
                    icon: action.icon.rawValue,
                    confirmBeforeRun: action.confirmBeforeRun
                )
            }
        }
        return SettingsExtensions(
            protectHost: protectHost,
            protectCertificateFingerprint: protectCertificateFingerprint,
            protectConsoleName: protectConsoleName,
            muteSchedule: muteSchedule,
            muteShort: muteShort,
            muteLong: muteLong,
            appearance: appearance,
            mappings: mappingValues,
            actions: actionValues
        )
    }

    private func persist() {
        let plaintextTokenIDs = syncActionTokensToKeychain()
        let encoder = JSONEncoder()
        encoder.userInfo[.plaintextActionTokenIDs] = plaintextTokenIDs
        if let data = try? encoder.encode(currentPersistedSettings()) {
            defaults.set(data, forKey: storageKey)
        }
        if let data = try? JSONEncoder().encode(currentExtensions()) {
            defaults.set(data, forKey: extensionsKey)
        }
    }

    // MARK: - Action tokens (keychain)

    /// Tokens as last written to the keychain, to skip redundant writes
    /// (`persist()` runs on every keystroke in the settings).
    private var keychainTokens: [UUID: String] = [:]

    /// Fills in each action's bearer token from the keychain. A token that is
    /// still present in the decoded data (written by 1.1.0 in plain text) is
    /// kept and moved into the keychain by the next `persist()`.
    private static func loadActionTokens(
        into mappings: [WebhookMapping]
    ) -> (mappings: [WebhookMapping], fromKeychain: [UUID: String]) {
        var fromKeychain: [UUID: String] = [:]
        let filled = mappings.map { mapping in
            var updated = mapping
            updated.actions = mapping.actions.map { action in
                var action = action
                if action.bearerToken.isEmpty,
                   let token = KeychainStore.string(
                       service: KeychainStore.actionTokenService,
                       account: action.id.uuidString
                   ) {
                    action.bearerToken = token
                    fromKeychain[action.id] = token
                }
                return action
            }
            return updated
        }
        return (filled, fromKeychain)
    }

    /// Writes changed tokens to the keychain and removes those of deleted
    /// actions. Returns the ids whose token could not be stored there; they
    /// stay in plain text so the token is never lost.
    private func syncActionTokensToKeychain() -> Set<UUID> {
        var current: [UUID: String] = [:]
        for action in mappings.flatMap(\.actions) where !action.bearerToken.isEmpty {
            current[action.id] = action.bearerToken
        }

        var failed = Set<UUID>()
        for (id, token) in current where keychainTokens[id] != token {
            if KeychainStore.set(token, service: KeychainStore.actionTokenService, account: id.uuidString) {
                keychainTokens[id] = token
            } else {
                failed.insert(id)
            }
        }

        // Removed actions or cleared tokens.
        for id in keychainTokens.keys where current[id] == nil {
            KeychainStore.delete(service: KeychainStore.actionTokenService, account: id.uuidString)
            keychainTokens[id] = nil
        }

        return failed
    }

    // MARK: - Configuration export / import

    /// Bumped whenever the exported envelope format changes incompatibly.
    static let configSchemaVersion = 1

    /// Portable wrapper written to / read from a shared config file so the same
    /// setup (installation ID, cameras, preferences) can be moved between Macs.
    private struct ConfigEnvelope: Codable {
        var schemaVersion: Int
        var settings: PersistedSettings
    }

    enum ConfigTransferError: LocalizedError {
        case unreadable
        case unsupportedVersion(Int)

        var errorDescription: String? {
            switch self {
            case .unreadable:
                return "Die Datei ist keine gültige Konfiguration."
            case .unsupportedVersion(let version):
                return "Die Konfiguration wurde mit einer neueren App-Version erstellt (Format \(version)). Bitte aktualisiere die App und versuche es erneut."
            }
        }
    }

    /// Serializes the full configuration (including installation ID) for export.
    func exportedConfigurationData() throws -> Data {
        var exported = currentPersistedSettings()
        exported.protectCertificateFingerprint = nil
        // Active mutes are runtime state, not configuration.
        exported.muteSchedule = nil
        exported.muteUntil = nil
        let envelope = ConfigEnvelope(schemaVersion: Self.configSchemaVersion, settings: exported)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // Exports carry the tokens so an import on another Mac works as-is.
        encoder.userInfo[.includeActionTokens] = true
        return try encoder.encode(envelope)
    }

    /// Replaces the current configuration with a previously exported one.
    func importConfiguration(from data: Data) throws {
        guard let envelope = try? JSONDecoder().decode(ConfigEnvelope.self, from: data) else {
            throw ConfigTransferError.unreadable
        }
        guard envelope.schemaVersion <= Self.configSchemaVersion else {
            throw ConfigTransferError.unsupportedVersion(envelope.schemaVersion)
        }
        apply(envelope.settings)
    }

    /// Applies imported settings to the live store. Each assignment goes through
    /// the published properties' `didSet`, so the new state is persisted and the
    /// UI updates. Optional fields fall back to the current value when absent.
    private func apply(_ saved: PersistedSettings) {
        if let id = saved.installationId, !id.isEmpty {
            installationId = id
        }
        mappings = saved.mappings
        defaultPosition = saved.defaultPosition
        edgeMargin = saved.edgeMargin
        autoCloseTimeout = saved.autoCloseTimeout
        screenTarget = saved.screenTarget
        showAllActiveCameras = saved.showAllActiveCameras ?? showAllActiveCameras
        autoUpdate = saved.autoUpdate ?? autoUpdate
        disableDuringDND = saved.disableDuringDND ?? disableDuringDND
        // Mutes are never imported (nor exported); current ones only lose removed cameras.
        pruneMutes()
        muteShort = saved.muteShort ?? muteShort
        muteLong = saved.muteLong ?? muteLong
        appearance = saved.appearance ?? appearance
        launchAtLogin = saved.launchAtLogin
        // Never trust a pin from a file. A different console means the stored
        // API key must not be sent there: drop key and pin, setup must be re-run.
        if let host = saved.protectHost,
           Self.normalizedHost(host) != Self.normalizedHost(protectHost) {
            protectAPIKey = ""
            protectCertificateFingerprint = nil
            protectHost = ProtectClient.canonicalHost(host) ?? host
        }
        if let name = saved.protectConsoleName {
            protectConsoleName = name
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
