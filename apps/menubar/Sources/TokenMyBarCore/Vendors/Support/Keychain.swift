import Foundation
import Security

/// Minimal read-only macOS Keychain accessor for provider credentials.
///
/// TokenMyBar only ever *reads* generic-password items that belong to the
/// provider CLIs the user already authenticated (e.g. Claude Code, Chromium
/// "Safe Storage" keys). It never writes, deletes, or stores secrets.
///
/// Reading an item owned by another application triggers the standard macOS
/// access dialog, which is the explicit, OS-enforced user consent the privacy
/// doc requires. We never bypass that prompt.
enum Keychain {
    /// Returns the raw secret data for a generic-password item, or `nil` when
    /// the item is absent or access is denied.
    static func genericPassword(service: String, account: String? = nil) -> Data? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if let account {
            query[kSecAttrAccount as String] = account
        }

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return data
    }

    /// Convenience for items whose secret is a UTF-8 string.
    static func genericPasswordString(service: String, account: String? = nil) -> String? {
        guard let data = genericPassword(service: service, account: account) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Returns the data for *every* generic-password item matching `service`,
    /// so callers can deterministically pick the right one rather than relying
    /// on `kSecMatchLimitOne` returning an arbitrary match when several exist.
    ///
    /// `SecItemCopyMatching` rejects `kSecMatchLimitAll` combined with
    /// `kSecReturnData` (errSecParam), so this enumerates item attributes
    /// first and then fetches each item's secret individually — which also
    /// lets the OS show its consent prompt per item.
    static func genericPasswords(service: String) -> [Data] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let attributes = item as? [[String: Any]] else {
            // Attribute enumeration unavailable — fall back to the single-item
            // path so one readable credential still works.
            return genericPassword(service: service).map { [$0] } ?? []
        }

        return attributes.compactMap { attribute in
            genericPassword(service: service, account: attribute[kSecAttrAccount as String] as? String)
        }
    }
}
