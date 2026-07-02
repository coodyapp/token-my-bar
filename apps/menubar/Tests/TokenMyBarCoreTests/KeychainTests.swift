import Foundation
import Security
import Testing
@testable import TokenMyBarCore

/// `SecItemCopyMatching` rejects `kSecMatchLimitAll` + `kSecReturnData`
/// (errSecParam), so `genericPasswords` must enumerate attributes first and
/// fetch each item's data individually. This exercises the real Keychain with
/// items owned by the test process, so no consent prompt is involved.
@Test func keychainGenericPasswordsReturnsAllItemsForService() throws {
    let service = "TokenMyBarTests-\(UUID().uuidString)"
    defer {
        for account in ["first", "second"] {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            SecItemDelete(query as CFDictionary)
        }
    }

    for (account, secret) in [("first", "one"), ("second", "two")] {
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(secret.utf8),
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        // Environments without an unlocked keychain can't run this test.
        guard status == errSecSuccess else { return }
    }

    let values = Set(Keychain.genericPasswords(service: service).map { String(decoding: $0, as: UTF8.self) })
    #expect(values == ["one", "two"])
}
