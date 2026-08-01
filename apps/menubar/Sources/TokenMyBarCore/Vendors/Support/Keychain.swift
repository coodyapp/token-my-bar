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
    /// Each read of another app's item can raise the consent dialog, and a
    /// background refresh every few minutes turns that into a password prompt
    /// several times an hour. Reads are answered from memory for an hour so a
    /// running app asks once; `invalidate()` drops the cache when the user
    /// explicitly asks to refresh, which is when re-asking is what they want.
    ///
    /// Failures are cached too — a denied or absent item re-prompting on every
    /// tick is the same problem wearing a different hat.
    private static let cacheTTL: TimeInterval = 3600
    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cache: [String: (data: [Data], readAt: Date)] = [:]

    static func invalidate() {
        cacheLock.lock()
        cache.removeAll()
        cacheLock.unlock()
    }

    private static func cached(_ key: String, now: Date = Date()) -> [Data]? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        guard let entry = cache[key], now.timeIntervalSince(entry.readAt) < cacheTTL else { return nil }
        return entry.data
    }

    private static func store(_ key: String, _ value: [Data], now: Date = Date()) {
        cacheLock.lock()
        cache[key] = (value, now)
        cacheLock.unlock()
    }

    /// Returns the raw secret data for a generic-password item, or `nil` when
    /// the item is absent or access is denied.
    static func genericPassword(service: String, account: String? = nil) -> Data? {
        let key = "one:\(service)|\(account ?? "")"
        if let hit = cached(key) { return hit.first }

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
        guard status == errSecSuccess, let data = item as? Data else {
            store(key, [])
            return nil
        }
        store(key, [data])
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
    /// `kSecReturnData` (errSecParam), so this enumerates persistent references
    /// first and then fetches each item's secret by its unique reference —
    /// which also lets the OS show its consent prompt per item.
    ///
    /// Persistent refs (not `(service, account)` re-queries) are used so that
    /// several items sharing the same service *and* account — e.g. iCloud-synced
    /// duplicates — resolve to distinct secrets instead of collapsing to the
    /// first match `kSecMatchLimitOne` happens to return.
    static func genericPasswords(service: String) -> [Data] {
        let cacheKey = "all:\(service)"
        if let hit = cached(cacheKey) { return hit }
        let found = readGenericPasswords(service: service)
        store(cacheKey, found)
        return found
    }

    private static func readGenericPasswords(service: String) -> [Data] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnPersistentRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let refs = item as? [Data] else {
            // Enumeration unavailable — fall back to the single-item path so one
            // readable credential still works.
            return genericPassword(service: service).map { [$0] } ?? []
        }

        return refs.compactMap { ref in
            let refQuery: [String: Any] = [
                kSecValuePersistentRef as String: ref,
                kSecReturnData as String: true,
            ]
            var data: CFTypeRef?
            guard SecItemCopyMatching(refQuery as CFDictionary, &data) == errSecSuccess else { return nil }
            return data as? Data
        }
    }
}
