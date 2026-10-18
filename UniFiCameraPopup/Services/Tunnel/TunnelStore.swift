import Foundation
import ProtectKit

/// WireGuard setup of this Mac. The config text (it contains the private key) lives
/// only in the keychain; UserDefaults keep the non-secret `TunnelRecord`. Deliberately
/// outside `SettingsStore`: the configuration export must never carry any of it.
@MainActor
final class TunnelStore: ObservableObject {
    static let shared = TunnelStore()
    static let defaultsKey = "unifi.camera.popup.tunnel"

    @Published private(set) var record: TunnelRecord

    #if DEBUG
    /// `--render-snapshots` reads a throwaway suite, never the real defaults.
    private let defaults = SnapshotRenderer.isActive ? SnapshotRenderer.isolatedDefaults : UserDefaults.standard
    #else
    private let defaults = UserDefaults.standard
    #endif
    private let keychainService = KeychainStore.wireGuardConfigService
    private let account = "default"

    private init() {
        let stored = TunnelRecord.decode(defaults.data(forKey: Self.defaultsKey))
        let hasItem = KeychainStore.string(service: keychainService, account: account) != nil
        record = stored.reconciled(hasKeychainItem: hasItem)
        if record != stored { persist() }
    }

    var mode: TunnelMode {
        get { record.mode }
        set { record.mode = newValue; persist() }
    }
    var fileName: String? { record.fileName }
    var summary: TunnelConfigSummary? { record.summary }
    var lastConnection: TunnelLastConnection? { record.lastConnection }
    var hasConfiguration: Bool { record.hasConfiguration }

    /// The full wg-quick text including the private key. Never log it.
    var configText: String? {
        KeychainStore.string(service: keychainService, account: account)
    }

    /// Stores a config the Go parser accepted. False when the keychain refused it.
    @discardableResult
    func save(config: String, fileName: String, summary: TunnelConfigSummary) -> Bool {
        guard KeychainStore.set(config, service: keychainService, account: account) else { return false }
        record = TunnelRecord(mode: record.mode, fileName: fileName, summary: summary, lastConnection: nil)
        persist()
        return true
    }

    func recordConnection(at date: Date, via kind: NetworkKind) {
        record.lastConnection = TunnelLastConnection(date: date, via: kind)
        persist()
    }

    func remove() {
        KeychainStore.delete(service: keychainService, account: account)
        record = TunnelRecord(mode: record.mode)
        persist()
    }

    #if DEBUG
    /// Sample record for `--render-snapshots` (S6); never persisted.
    func snapshotSeed(_ sample: TunnelRecord) {
        guard SnapshotRenderer.isActive else { return }
        record = sample
    }
    #endif

    private func persist() {
        #if DEBUG
        if SnapshotRenderer.isActive { return }
        #endif
        defaults.set(record.encoded(), forKey: Self.defaultsKey)
    }
}
