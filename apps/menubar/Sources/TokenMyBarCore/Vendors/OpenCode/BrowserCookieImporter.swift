import CSQLite3
import Foundation

/// Imports `opencode.ai` session cookies from local browsers.
///
/// Supports Chromium-family browsers (Arc, Chrome, Brave, Edge, Chromium,
/// Vivaldi) via `v10` AES decryption and Firefox via its plaintext cookie
/// store. The importer only reads a browser's Safe Storage Keychain key when
/// that browser actually holds a matching cookie, so users are not prompted for
/// browsers they never signed into.
public enum BrowserCookieImporter {
    public struct Cookie: Equatable, Sendable {
        public let name: String
        public let value: String
    }

    struct ChromiumBrowser {
        let userDataSubpath: String
        let safeStorageService: String
        let safeStorageAccount: String
    }

    static let chromiumBrowsers: [ChromiumBrowser] = [
        .init(userDataSubpath: "Arc/User Data", safeStorageService: "Arc Safe Storage", safeStorageAccount: "Arc"),
        .init(userDataSubpath: "Google/Chrome", safeStorageService: "Chrome Safe Storage", safeStorageAccount: "Chrome"),
        .init(userDataSubpath: "BraveSoftware/Brave-Browser", safeStorageService: "Brave Safe Storage", safeStorageAccount: "Brave"),
        .init(userDataSubpath: "Microsoft Edge", safeStorageService: "Microsoft Edge Safe Storage", safeStorageAccount: "Microsoft Edge"),
        .init(userDataSubpath: "Chromium", safeStorageService: "Chromium Safe Storage", safeStorageAccount: "Chromium"),
        .init(userDataSubpath: "Vivaldi", safeStorageService: "Vivaldi Safe Storage", safeStorageAccount: "Vivaldi"),
    ]

    /// Builds a `Cookie:` header value (`name=value; ...`) for the domain, or
    /// `nil` when no matching cookie is found in any browser.
    public static func cookieHeader(domain: String = "opencode.ai") -> String? {
        let cookies = importCookies(domain: domain)
        guard !cookies.isEmpty else { return nil }
        return cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    static func importCookies(domain: String) -> [Cookie] {
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)

        for browser in chromiumBrowsers {
            let root = appSupport.appendingPathComponent(browser.userDataSubpath, isDirectory: true)
            let cookies = chromiumCookies(browser: browser, root: root, domain: domain)
            if !cookies.isEmpty { return cookies }
        }

        return firefoxCookies(domain: domain)
    }

    // MARK: - Host / expiry filtering

    /// True when `host` is the domain itself or one of its subdomains.
    /// Anchored so look-alikes (`myopencode.ai`, `opencode.ai.attacker.com`)
    /// never match and get their cookies sent to the real domain.
    static func hostMatches(_ host: String, domain: String) -> Bool {
        host == domain || host == "." + domain || host.hasSuffix("." + domain)
    }

    /// Chromium `expires_utc` is microseconds since 1601-01-01; `0` marks a
    /// non-persistent session cookie, which is still valid.
    static func isUnexpiredChromium(expiresUtc: Int64, now: Date = Date()) -> Bool {
        guard expiresUtc != 0 else { return true }
        let nowMicros = Int64((now.timeIntervalSince1970 + 11_644_473_600) * 1_000_000)
        return expiresUtc > nowMicros
    }

    /// Firefox `expiry` is Unix seconds; `0` marks a session cookie.
    static func isUnexpiredFirefox(expiry: Int64, now: Date = Date()) -> Bool {
        guard expiry != 0 else { return true }
        return expiry > Int64(now.timeIntervalSince1970)
    }

    // MARK: - Chromium

    private static func chromiumCookies(browser: ChromiumBrowser, root: URL, domain: String) -> [Cookie] {
        let dbs = cookieDatabases(under: root)
        guard !dbs.isEmpty else { return [] }

        // First pass: see if any DB holds the domain before touching Keychain.
        let encrypted = dbs.flatMap { readChromiumRows(dbPath: $0.path, domain: domain) }
        guard !encrypted.isEmpty else { return [] }

        guard let password = Keychain.genericPasswordString(
            service: browser.safeStorageService,
            account: browser.safeStorageAccount
        ), let key = ChromiumCookieDecryptor.deriveKey(safeStoragePassword: password) else {
            return []
        }

        return encrypted.compactMap { row in
            guard let value = ChromiumCookieDecryptor.decrypt(encryptedValue: row.encryptedValue, key: key) else {
                return nil
            }
            return Cookie(name: row.name, value: value)
        }
    }

    private static func cookieDatabases(under root: URL) -> [URL] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        var dbs: [URL] = []
        for entry in entries {
            let direct = entry.appendingPathComponent("Cookies")
            if fm.fileExists(atPath: direct.path) { dbs.append(direct) }
            let network = entry.appendingPathComponent("Network/Cookies")
            if fm.fileExists(atPath: network.path) { dbs.append(network) }
        }
        return dbs
    }

    private struct ChromiumRow {
        let name: String
        let encryptedValue: Data
    }

    private static func readChromiumRows(dbPath: String, domain: String, now: Date = Date()) -> [ChromiumRow] {
        readDatabaseCopy(dbPath: dbPath) { db in
            var rows: [ChromiumRow] = []
            // LIKE is a coarse prefilter; hostMatches/expiry below apply the
            // precise, anchored rules the SQL LIKE can't express safely.
            let sql = "SELECT name, encrypted_value, host_key, expires_utc FROM cookies WHERE host_key LIKE ?;"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_text(statement, 1, "%\(domain)%", -1, sqliteTransient)
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let namePtr = sqlite3_column_text(statement, 0),
                      let hostPtr = sqlite3_column_text(statement, 2) else { continue }
                guard hostMatches(String(cString: hostPtr), domain: domain),
                      isUnexpiredChromium(expiresUtc: sqlite3_column_int64(statement, 3), now: now) else { continue }
                let name = String(cString: namePtr)
                if let blob = sqlite3_column_blob(statement, 1) {
                    let length = Int(sqlite3_column_bytes(statement, 1))
                    let data = Data(bytes: blob, count: length)
                    rows.append(ChromiumRow(name: name, encryptedValue: data))
                }
            }
            return rows
        } ?? []
    }

    // MARK: - Firefox

    private static func firefoxCookies(domain: String) -> [Cookie] {
        let profiles = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Firefox/Profiles", isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(at: profiles, includingPropertiesForKeys: nil) else {
            return []
        }
        for profile in entries {
            let db = profile.appendingPathComponent("cookies.sqlite")
            guard FileManager.default.fileExists(atPath: db.path) else { continue }
            let cookies = readDatabaseCopy(dbPath: db.path) { handle -> [Cookie] in
                var rows: [Cookie] = []
                let sql = "SELECT name, value, host, expiry FROM moz_cookies WHERE host LIKE ?;"
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
                defer { sqlite3_finalize(statement) }
                sqlite3_bind_text(statement, 1, "%\(domain)%", -1, sqliteTransient)
                while sqlite3_step(statement) == SQLITE_ROW {
                    guard let namePtr = sqlite3_column_text(statement, 0),
                          let valuePtr = sqlite3_column_text(statement, 1),
                          let hostPtr = sqlite3_column_text(statement, 2) else { continue }
                    guard hostMatches(String(cString: hostPtr), domain: domain),
                          isUnexpiredFirefox(expiry: sqlite3_column_int64(statement, 3)) else { continue }
                    rows.append(Cookie(name: String(cString: namePtr), value: String(cString: valuePtr)))
                }
                return rows
            } ?? []
            if !cookies.isEmpty { return cookies }
        }
        return []
    }

    // MARK: - SQLite helpers

    /// Copies the database to a temp file (browser stores stay locked while the
    /// browser runs) and opens it read-only.
    private static func readDatabaseCopy<T>(dbPath: String, _ body: (OpaquePointer) -> T) -> T? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dbPath) else { return nil }
        let temp = fm.temporaryDirectory.appendingPathComponent("tmb-cookies-\(UUID().uuidString).sqlite")
        defer { try? fm.removeItem(at: temp) }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: dbPath)),
              fm.createFile(atPath: temp.path, contents: data, attributes: [.posixPermissions: 0o600])
        else { return nil }

        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(temp.path, &db, flags, nil) == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }
            return nil
        }
        defer { sqlite3_close(db) }
        return body(db)
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
