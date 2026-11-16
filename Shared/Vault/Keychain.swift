import Foundation
import Security

/// Minimal wrapper over generic-password Keychain items.
///
/// - Synced through iCloud Keychain (`kSecAttrSynchronizable`), so secrets follow
///   the user to their other devices without passing through CloudKit or Typo.
/// - Readable only while the device is unlocked.
/// - Shared between the iOS and Mac apps through one access group
///   (`TypoKeychainGroup` in Info.plist, set from `$(AppIdentifierPrefix)`).
///
/// Note: iOS can't sync a Keychain item that also demands Face ID at the OS level,
/// so Face ID for the vault is enforced by the app (`VaultLock`).
enum Keychain {
    enum Service: String {
        case vault = "com.starconnect.typo.vault"
        case wifi = "com.starconnect.typo.wifi"
    }

    enum KeychainError: LocalizedError {
        case status(OSStatus)
        var errorDescription: String? {
            if case .status(let s) = self { return (SecCopyErrorMessageString(s, nil) as String?) ?? "Keychain error \(s)" }
            return nil
        }
    }

    private static var accessGroup: String? {
        Bundle.main.object(forInfoDictionaryKey: "TypoKeychainGroup") as? String
    }

    private static func base(_ service: Service, account: String?) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service.rawValue,
            kSecAttrSynchronizable as String: kCFBooleanTrue as Any,
            kSecUseDataProtectionKeychain as String: kCFBooleanTrue as Any,
        ]
        if let account { q[kSecAttrAccount as String] = account }
        if let accessGroup { q[kSecAttrAccessGroup as String] = accessGroup }
        return q
    }

    static func set(_ data: Data, service: Service, account: String) throws {
        let query = base(service, account: account)
        let update: [String: Any] = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    static func get(service: Service, account: String) -> Data? {
        var query = base(service, account: account)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    /// All items for a service, as (account, data).
    static func all(service: Service) -> [(account: String, data: Data)] {
        var query = base(service, account: nil)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecReturnAttributes as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let account = item[kSecAttrAccount as String] as? String,
                  let data = item[kSecValueData as String] as? Data else { return nil }
            return (account, data)
        }
    }

    static func delete(service: Service, account: String) {
        SecItemDelete(base(service, account: account) as CFDictionary)
    }

    // Convenience for strings (Wi-Fi passwords).
    static func setString(_ value: String, service: Service, account: String) throws {
        try set(Data(value.utf8), service: service, account: account)
    }

    static func string(service: Service, account: String) -> String? {
        get(service: service, account: account).flatMap { String(data: $0, encoding: .utf8) }
    }
}
