import CommonCrypto
import Foundation

/// Decrypts Chromium (`v10`) cookie blobs as stored on macOS.
///
/// Chromium derives an AES-128 key from a per-browser "Safe Storage" Keychain
/// password via PBKDF2-HMAC-SHA1 (salt `saltysalt`, 1003 rounds) and encrypts
/// cookie values with AES-128-CBC and a fixed 16-space IV. Modern Chromium
/// (m130+) also prepends a 32-byte SHA-256 domain hash to the plaintext, which
/// we strip when present.
enum ChromiumCookieDecryptor {
    static let versionPrefix = "v10"
    private static let salt = "saltysalt"
    private static let rounds: UInt32 = 1003
    private static let keyLength = 16
    private static let domainHashLength = 32

    /// Derives the AES key from a Safe Storage password (the Keychain secret).
    static func deriveKey(safeStoragePassword: String) -> Data? {
        let passwordBytes = Array(safeStoragePassword.utf8)
        let saltBytes = Array(salt.utf8)
        var derived = [UInt8](repeating: 0, count: keyLength)

        let status = saltBytes.withUnsafeBufferPointer { saltPtr in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                passwordBytes.map { Int8(bitPattern: $0) }, passwordBytes.count,
                saltPtr.baseAddress, saltPtr.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                rounds,
                &derived, keyLength
            )
        }
        guard status == kCCSuccess else { return nil }
        return Data(derived)
    }

    /// Decrypts a raw `encrypted_value` blob (including the `v10` prefix) into a
    /// cookie string. Returns `nil` for unsupported versions or decryption
    /// failures.
    static func decrypt(encryptedValue: Data, key: Data) -> String? {
        guard encryptedValue.count > versionPrefix.count else { return nil }
        let prefix = String(decoding: encryptedValue.prefix(versionPrefix.count), as: UTF8.self)
        guard prefix == versionPrefix else { return nil }

        let ciphertext = encryptedValue.dropFirst(versionPrefix.count)
        guard !ciphertext.isEmpty, ciphertext.count % kCCBlockSizeAES128 == 0 else { return nil }

        let iv = [UInt8](repeating: 0x20, count: kCCBlockSizeAES128)
        var output = [UInt8](repeating: 0, count: ciphertext.count + kCCBlockSizeAES128)
        var decryptedCount = 0

        let status = key.withUnsafeBytes { keyPtr in
            Data(ciphertext).withUnsafeBytes { dataPtr in
                CCCrypt(
                    CCOperation(kCCDecrypt),
                    CCAlgorithm(kCCAlgorithmAES),
                    CCOptions(kCCOptionPKCS7Padding),
                    keyPtr.baseAddress, key.count,
                    iv,
                    dataPtr.baseAddress, dataPtr.count,
                    &output, output.count,
                    &decryptedCount
                )
            }
        }
        guard status == kCCSuccess else { return nil }
        return cookieString(from: Data(output.prefix(decryptedCount)))
    }

    /// Converts decrypted bytes into a printable cookie string, stripping the
    /// 32-byte domain-hash prefix that newer Chromium versions add.
    static func cookieString(from data: Data) -> String? {
        if let direct = printableString(data) { return direct }
        guard data.count > domainHashLength else { return nil }
        return printableString(data.dropFirst(domainHashLength))
    }

    private static func printableString<S: Sequence>(_ bytes: S) -> String? where S.Element == UInt8 {
        let data = Data(bytes)
        guard !data.isEmpty, data.allSatisfy({ $0 >= 0x20 && $0 != 0x7F }) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
