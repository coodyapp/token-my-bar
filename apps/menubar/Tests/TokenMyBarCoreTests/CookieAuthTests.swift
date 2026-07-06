import Foundation
import Testing
@testable import TokenMyBarCore

@Test func chromiumDecryptorDerivesStableKey() {
    // Deterministic PBKDF2-HMAC-SHA1 (salt "saltysalt", 1003 rounds, 16 bytes).
    let key = ChromiumCookieDecryptor.deriveKey(safeStoragePassword: "peanuts")
    #expect(key?.count == 16)
    #expect(key?.map { String(format: "%02x", $0) }.joined() == "d9a09d499b4e1b7461f28e67972c6dbd")
}

@Test func chromiumDecryptorStripsDomainHashPrefix() {
    // Real Chromium (m130+) prepends a 32-byte SHA-256 domain hash before the
    // printable cookie value.
    let prefix = Data((0..<32).map { _ in UInt8(0x01) })
    let value = Data("Fe26.2**deadbeef".utf8)
    #expect(ChromiumCookieDecryptor.cookieString(from: prefix + value) == "Fe26.2**deadbeef")
}

@Test func chromiumDecryptorKeepsPlainValueWithoutPrefix() {
    #expect(ChromiumCookieDecryptor.cookieString(from: Data("session=abc".utf8)) == "session=abc")
}

@Test func chromiumDecryptorRejectsUnsupportedVersion() {
    let blob = Data("v99".utf8) + Data(repeating: 0, count: 16)
    #expect(ChromiumCookieDecryptor.decrypt(encryptedValue: blob, key: Data(repeating: 0, count: 16)) == nil)
}

@Test func claudeKeychainPayloadPrefersClaudeAiOauthBlock() {
    let payload: [String: Any] = [
        "mcpOAuth": ["accessToken": "mcp-should-not-win"],
        "claudeAiOauth": ["accessToken": "sk-ant-oat-correct", "subscriptionType": "pro"],
    ]
    #expect(ClaudeOAuthUsageProvider.tokenFromKeychainPayload(payload) == "sk-ant-oat-correct")
}

@Test func claudeKeychainPayloadFallsBackToFlatToken() {
    #expect(ClaudeOAuthUsageProvider.tokenFromKeychainPayload(["access_token": "flat"]) == "flat")
}

@Test func cookieHostMatchAnchorsToDomainAndSubdomains() {
    #expect(BrowserCookieImporter.hostMatches("opencode.ai", domain: "opencode.ai"))
    #expect(BrowserCookieImporter.hostMatches(".opencode.ai", domain: "opencode.ai"))
    #expect(BrowserCookieImporter.hostMatches("app.opencode.ai", domain: "opencode.ai"))
    // Look-alike domains must NOT match (would otherwise be sent to opencode.ai).
    #expect(!BrowserCookieImporter.hostMatches("notopencode.ai", domain: "opencode.ai"))
    #expect(!BrowserCookieImporter.hostMatches("myopencode.ai", domain: "opencode.ai"))
    #expect(!BrowserCookieImporter.hostMatches("opencode.ai.attacker.com", domain: "opencode.ai"))
}

@Test func cookieExpiryKeepsSessionAndFutureDropsExpired() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    // Chromium expires_utc is microseconds since 1601-01-01; 0 means a session cookie.
    let nowMicros1601 = Int64((now.timeIntervalSince1970 + 11_644_473_600) * 1_000_000)
    #expect(BrowserCookieImporter.isUnexpiredChromium(expiresUtc: 0, now: now))
    #expect(BrowserCookieImporter.isUnexpiredChromium(expiresUtc: nowMicros1601 + 1_000_000, now: now))
    #expect(!BrowserCookieImporter.isUnexpiredChromium(expiresUtc: nowMicros1601 - 1_000_000, now: now))
    // Firefox expiry is Unix seconds; 0 means a session cookie.
    #expect(BrowserCookieImporter.isUnexpiredFirefox(expiry: 0, now: now))
    #expect(BrowserCookieImporter.isUnexpiredFirefox(expiry: 1_000_500, now: now))
    #expect(!BrowserCookieImporter.isUnexpiredFirefox(expiry: 999_999, now: now))
}

@Test func opencodeParsesWorkspaceIDsInOrder() {
    let text = #"[$R[1]={id:"wrk_01AAA",name:"Coody"},$R[2]={id:"wrk_01BBB",name:"Augusto"}]"#
    #expect(OpenCodeCookieUsageProvider.workspaceIDs(in: text) == ["wrk_01AAA", "wrk_01BBB"])
}

@Test func opencodeParsesUsagePageWindows() {
    // Mirrors the real opencode.ai workspace page (resetInSec before usagePercent,
    // plus a decoy "monthlyUsage:0," that must not be matched).
    let page = """
    ...monthlyUsage:0,timeMonthlyUsageUpdated:$R[30]=new Date("2026-03-10T00:56:44.000Z"),\
    rollingUsage:$R[33]={status:"ok",resetInSec:18000,usagePercent:0},\
    weeklyUsage:$R[34]={status:"ok",resetInSec:543686,usagePercent:8},\
    monthlyUsage:$R[35]={status:"ok",resetInSec:1989328,usagePercent:6}...
    """
    let object = OpenCodeCookieUsageProvider.parseUsagePage(page)
    let snapshot = OpenCodeCookieUsageProvider.snapshot(from: object ?? [:])
    #expect(snapshot.status == .ok)
    #expect(snapshot.usageRows.map(\.title) == ["Rolling Usage", "Weekly Usage", "Monthly Usage"])
    #expect(snapshot.usageRows.map(\.value) == ["0%", "8%", "6%"])
}

@Test func opencodeUsagePageReturnsNilWhenNoWindows() {
    #expect(OpenCodeCookieUsageProvider.parseUsagePage("<html>nothing here</html>") == nil)
}
