import AppCore
import Foundation
import Security

/// Secrets that must not be stored in plain text in UserDefaults (API key, WireGuard config,
/// bearer tokens). Since 2.0.0 all of them live in ONE generic-password item of the login keychain
/// (`vaultService`, a `SecretVault` as JSON): without an Apple team ID macOS asks for the keychain
/// password per item after every update, so one item keeps that to a single prompt. The item is read
/// once per launch and kept in memory; `service`/`account` address an entry inside it.
enum KeychainStore {
    static let actionTokenService = "com.snackbits.UniFiCameraPopup.action-token"
    static let protectAPIKeyService = "com.snackbits.UniFiCameraPopup.protect-api-key"
    /// Bearer tokens of event rules (Kameras › Ereignisse); account = rule id. Never exported.
    static let ruleTokenService = "com.snackbits.UniFiCameraPopup.rule-token"
    /// Full wg-quick text of the WireGuard tunnel (contains the private key).
    static let wireGuardConfigService = "com.snackbits.UniFiCameraPopup.wireguard-config"
    /// The single keychain item holding all of the above.
    static let vaultService = "com.snackbits.UniFiCameraPopup.secrets"
    private static let vaultAccount = "vault"
    /// Before 2.0.0 every service above was its own keychain item; moved into the vault once.
    private static let legacyServices = [actionTokenService, protectAPIKeyService, ruleTokenService, wireGuardConfigService]

    private enum State {
        case notLoaded
        case loaded(SecretVault, itemExists: Bool)
        /// Refused (e.g. „Deny“) or unreadable: no secrets until the next launch, nothing is written,
        /// so a refused prompt never overwrites the stored item and is not shown again and again.
        case unavailable
    }

    private static let lock = NSLock()
    private static var state = State.notLoaded

    static func string(service: String, account: String) -> String? {
        #if DEBUG
        // `--render-snapshots` never touches the real keychain (a prompt would block the run).
        if SnapshotRenderer.isActive { return service == protectAPIKeyService ? "snapshot-sample-key" : nil }
        #endif
        lock.lock()
        defer { lock.unlock() }
        guard case .loaded(let vault, _) = loadedState() else { return nil }
        return vault.value(service: service, account: account)
    }

    /// Stores or replaces the value. Returns `false` when the keychain refused.
    @discardableResult
    static func set(_ value: String, service: String, account: String) -> Bool {
        #if DEBUG
        if SnapshotRenderer.isActive { return true }
        #endif
        lock.lock()
        defer { lock.unlock() }
        guard case .loaded(var vault, let exists) = loadedState() else { return false }
        if vault.value(service: service, account: account) == value { return true }
        vault.set(value, service: service, account: account)
        return write(vault, itemExists: exists)
    }

    static func delete(service: String, account: String) {
        #if DEBUG
        if SnapshotRenderer.isActive { return }
        #endif
        lock.lock()
        defer { lock.unlock() }
        guard case .loaded(var vault, let exists) = loadedState(),
              vault.value(service: service, account: account) != nil else { return }
        vault.remove(service: service, account: account)
        write(vault, itemExists: exists)
    }

    /// Account names of every entry of `service`.
    static func accounts(service: String) -> [String] {
        #if DEBUG
        if SnapshotRenderer.isActive { return [] }
        #endif
        lock.lock()
        defer { lock.unlock() }
        guard case .loaded(let vault, _) = loadedState() else { return [] }
        return vault.accounts(service: service)
    }

    // MARK: Vault item (call with `lock` held)

    private static func loadedState() -> State {
        if case .notLoaded = state { state = load() }
        return state
    }

    private static func load() -> State {
        var query = itemQuery(service: vaultService, account: vaultAccount)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let vault = SecretVault.decode(data) else {
                NSLog("Keychain: secrets item is unreadable – leaving it untouched")
                return .unavailable
            }
            return .loaded(vault, itemExists: true)
        case errSecItemNotFound:
            return migrateLegacyItems()
        default:
            NSLog("Keychain read failed (\(status)) for the secrets item")
            return .unavailable
        }
    }

    /// First launch of 2.0.0: copies the old per-secret items into the vault, then deletes them –
    /// only after the vault was written, so nothing is lost when the keychain refuses.
    private static func migrateLegacyItems() -> State {
        var vault = SecretVault()
        var moved: [(service: String, account: String)] = []
        for service in legacyServices {
            for account in legacyAccounts(service: service) {
                var query = itemQuery(service: service, account: account)
                query[kSecReturnData as String] = true
                query[kSecMatchLimit as String] = kSecMatchLimitOne
                var result: CFTypeRef?
                let status = SecItemCopyMatching(query as CFDictionary, &result)
                guard status == errSecSuccess, let data = result as? Data,
                      let value = String(data: data, encoding: .utf8) else {
                    NSLog("Keychain: could not move an old item (\(status)) – trying again next launch")
                    return .unavailable
                }
                vault.set(value, service: service, account: account)
                moved.append((service, account))
            }
        }
        guard !moved.isEmpty else { return .loaded(vault, itemExists: false) }
        guard write(vault, itemExists: false) else { return .unavailable }
        for item in moved {
            SecItemDelete(itemQuery(service: item.service, account: item.account) as CFDictionary)
        }
        NSLog("Keychain: moved \(moved.count) old item(s) into the secrets item")
        return state
    }

    /// Attributes only – listing never asks for the password.
    private static func legacyAccounts(service: String) -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return [] }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }

    /// Writes the vault and updates `state`. An empty vault removes the item.
    @discardableResult
    private static func write(_ vault: SecretVault, itemExists: Bool) -> Bool {
        let query = itemQuery(service: vaultService, account: vaultAccount)
        if vault.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                NSLog("Keychain delete failed (\(status)) for the secrets item")
                return false
            }
            state = .loaded(vault, itemExists: false)
            return true
        }
        let data = vault.encoded()
        var status = itemExists
            ? SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            : errSecItemNotFound
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(addQuery as CFDictionary, nil)
            if status == errSecDuplicateItem {
                status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            }
        }
        guard status == errSecSuccess else {
            NSLog("Keychain write failed (\(status)) for the secrets item")
            return false
        }
        state = .loaded(vault, itemExists: true)
        return true
    }

    private static func itemQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
