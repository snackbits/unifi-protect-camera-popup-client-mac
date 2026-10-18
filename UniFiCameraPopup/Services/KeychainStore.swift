import Foundation
import Security

/// Minimal wrapper around generic-password items in the login keychain.
/// Used for secrets that must not be stored in plain text in UserDefaults
/// (e.g. the bearer tokens of camera action buttons).
enum KeychainStore {
    static let actionTokenService = "com.snackbits.UniFiCameraPopup.action-token"
    static let protectAPIKeyService = "com.snackbits.UniFiCameraPopup.protect-api-key"
    /// Bearer tokens of event rules (Kameras › Ereignisse); account = rule id. Never exported.
    static let ruleTokenService = "com.snackbits.UniFiCameraPopup.rule-token"
    /// Full wg-quick text of the WireGuard tunnel (contains the private key).
    static let wireGuardConfigService = "com.snackbits.UniFiCameraPopup.wireguard-config"

    static func string(service: String, account: String) -> String? {
        #if DEBUG
        // `--render-snapshots` never touches the real keychain (a prompt would block the run).
        if SnapshotRenderer.isActive { return service == protectAPIKeyService ? "snapshot-sample-key" : nil }
        #endif
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecItemNotFound {
                NSLog("Keychain read failed (\(status)) for \(account)")
            }
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Stores or replaces the value. Returns `false` when the keychain refused.
    @discardableResult
    static func set(_ value: String, service: String, account: String) -> Bool {
        #if DEBUG
        if SnapshotRenderer.isActive { return true }
        #endif
        let data = Data(value.utf8)
        let query = baseQuery(service: service, account: account)

        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return true }

        guard updateStatus == errSecItemNotFound else {
            NSLog("Keychain update failed (\(updateStatus)) for \(account)")
            return false
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess {
            NSLog("Keychain add failed (\(addStatus)) for \(account)")
        }
        return addStatus == errSecSuccess
    }

    static func delete(service: String, account: String) {
        #if DEBUG
        if SnapshotRenderer.isActive { return }
        #endif
        let status = SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
        if status != errSecSuccess, status != errSecItemNotFound {
            NSLog("Keychain delete failed (\(status)) for \(account)")
        }
    }

    private static func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
