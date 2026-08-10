import Foundation
import CryptoKit
import Security

/// Stores the unwrapped Data Encryption Key (DEK) in the macOS Keychain so the app
/// unlocks silently on this device after the first passphrase entry. The DEK is
/// marked `ThisDeviceOnly` and never synced — a second device (future iPhone)
/// re-derives it from the passphrase, so the key itself never travels.
enum KeychainStore {
    private static let service = "com.berjil.myos.vault"

    private static func account(_ username: String) -> String { "dek.\(username.lowercased())" }

    /// Persist the DEK for a user. Overwrites any existing entry.
    @discardableResult
    static func saveDEK(_ dek: SymmetricKey, username: String) -> Bool {
        let data = dek.withUnsafeBytes { Data($0) }
        let acct = account(username)
        // Delete-then-add keeps it simple and avoids stale-attribute update quirks.
        deleteDEK(username: username)
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrService as String: service,
            kSecAttrAccount as String: acct,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: data
        ]
        return SecItemAdd(attrs as CFDictionary, nil) == errSecSuccess
    }

    /// Load the DEK for a user, or nil if none is stored on this device.
    static func loadDEK(username: String) -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(username),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data, data.count == MyOSCrypto.dekBytes else { return nil }
        return SymmetricKey(data: data)
    }

    static func deleteDEK(username: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(username)
        ]
        SecItemDelete(query as CFDictionary)
    }
}
