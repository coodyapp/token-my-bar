import Foundation
import Testing
@testable import TokenMyBarCore

@Test func appConfigParsesPrimaryVendorAndTTL() {
    let config = AppConfig(contents: """
    [ui]
    primary = "claude"

    [refresh]
    ttl_seconds = 45
    """)

    #expect(config.primaryVendor == .claudeCode)
    #expect(config.refreshTTL == 45)
}

@Test func appConfigUsesDefaultsForInvalidValues() {
    let config = AppConfig(contents: """
    [ui]
    primary = nope

    [refresh]
    ttl_seconds = -1
    """)

    #expect(config.primaryVendor == nil)
    #expect(config.refreshTTL == AppConfig.defaultTTL)
}

@Test func appConfigTimerTTLNeverOutlastsTheChosenInterval() {
    let config = AppConfig()
    #expect(config.refreshTTL == 120)

    // "Every 1 minute" with a 120s TTL would return cache on every tick, so the
    // app would actually fetch every 2-3 minutes instead of every minute. The
    // margin also has to cover the fetch itself (up to the 20s provider timeout),
    // since cache age is measured from when the refresh finished writing.
    #expect(config.timerTTL(interval: RefreshInterval.oneMinute.seconds) == 30)
    #expect(config.timerTTL(interval: RefreshInterval.twoMinutes.seconds) == 60)
    // Intervals longer than the TTL keep the configured TTL.
    #expect(config.timerTTL(interval: RefreshInterval.fifteenMinutes.seconds) == 120)
    // Manual-only has no interval to bound.
    #expect(config.timerTTL(interval: RefreshInterval.manual.seconds) == 120)
}

@Test func appConfigParsesOpenCodeOverrides() {
    let config = AppConfig(contents: """
    [opencode]
    cookie = "auth=abc123; theme=dark"
    workspace_id = wrk_01ABC
    db = ~/Sessions/opencode.db
    """)

    // The `;` pairs of a cookie header survive: a quoted value is verbatim.
    #expect(config.openCodeCookie == "auth=abc123; theme=dark")
    #expect(config.openCodeWorkspaceID == "wrk_01ABC")
    #expect(config.openCodeDatabasePath == "~/Sessions/opencode.db")
    #expect(config.primaryVendor == nil)
    #expect(config.refreshTTL == AppConfig.defaultTTL)
}

@Test func appConfigDropsUnsafeWorkspaceID() {
    #expect(AppConfig(contents: "[opencode]\nworkspace_id = wrk?x=1").openCodeWorkspaceID == nil)
    #expect(AppConfig(contents: "[opencode]\nworkspace_id = ../../etc/passwd").openCodeWorkspaceID == nil)
    #expect(AppConfig(contents: "[opencode]\nworkspace_id = \"wrk abc\"").openCodeWorkspaceID == nil)
    // Paste the bare id, not the workspace URL: the whole URL is not an id.
    #expect(AppConfig(contents: "[opencode]\nworkspace_id = https://opencode.ai/workspace/wrk_01ABC").openCodeWorkspaceID == nil)
    #expect(AppConfig(contents: "[opencode]\nworkspace_id =").openCodeWorkspaceID == nil)
}

@Test func appConfigIgnoresGarbageAndKeepsDefaults() {
    for contents in ["", "\n\n", "# just a comment\n; and another", "not a config at all", "[opencode]\ncookie"] {
        let config = AppConfig(contents: contents)
        #expect(config == AppConfig())
        #expect(config.openCodeCookie == nil)
        #expect(config.openCodeWorkspaceID == nil)
        #expect(config.openCodeDatabasePath == nil)
    }
}

@Test func openCodeCookieFromConfigLosesToEnvironment() throws {
    let config = AppConfig(contents: "[opencode]\ncookie = \"auth=fromfile; x=1\"")

    unsetenv("TOKEN_MY_BAR_OPENCODE_COOKIE")
    #expect(try OpenCodeCookieUsageProvider.cookieHeader(config: config) == "auth=fromfile; x=1")

    setenv("TOKEN_MY_BAR_OPENCODE_COOKIE", "Cookie: auth=fromenv", 1)
    defer { unsetenv("TOKEN_MY_BAR_OPENCODE_COOKIE") }
    #expect(try OpenCodeCookieUsageProvider.cookieHeader(config: config) == "auth=fromenv")
}

@Test func openCodeDatabasePathFromConfigLosesToEnvironment() {
    let config = AppConfig(contents: "[opencode]\ndb = ~/Sessions/opencode.db")

    unsetenv("TOKEN_MY_BAR_OPENCODE_DB")
    #expect(
        OpenCodeLocalUsageProvider.defaultDatabaseURL(config: config).path
            == NSHomeDirectory() + "/Sessions/opencode.db"
    )

    setenv("TOKEN_MY_BAR_OPENCODE_DB", "/tmp/token-my-bar-env-opencode.db", 1)
    defer { unsetenv("TOKEN_MY_BAR_OPENCODE_DB") }
    #expect(OpenCodeLocalUsageProvider.defaultDatabaseURL(config: config).path == "/tmp/token-my-bar-env-opencode.db")
}

@Test func appConfigWarnsButStillLoadsACookieFromAWorldReadableFile() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).toml")
    try "[opencode]\ncookie = \"auth=abc\"".write(to: url, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: url) }

    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
    // The mode already leaked the cookie, so the override stays usable.
    #expect(AppConfig.load(from: url).openCodeCookie == "auth=abc")

    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    #expect(AppConfig.load(from: url).openCodeCookie == "auth=abc")
}

@Test func appConfigVendorAliases() {
    #expect(AppConfig.vendor(from: "openai") == .codex)
    #expect(AppConfig.vendor(from: "claude-code") == .claudeCode)
    #expect(AppConfig.vendor(from: "open-code") == .opencode)
}

@Test func appConfigParsesDisabledVendors() {
    let config = AppConfig(contents: """
    [vendors]
    disabled = claude-code, antigravity
    """)

    #expect(config.disabledVendors == [.claudeCode, .antigravity])
    #expect(config.enabledVendors == [.codex, .opencode])
}

@Test func appConfigDisabledVendorsDefaultsToNone() {
    #expect(AppConfig(contents: "").disabledVendors.isEmpty)
    #expect(AppConfig(contents: "").enabledVendors == ProviderID.allCases)
}

@Test func appConfigVendorAliasResolvesEveryRegisteredVendor() {
    // The CLI derives its help and validation from ProviderID.allCases; every
    // raw value has to resolve so the two can never drift apart.
    for id in ProviderID.allCases {
        #expect(AppConfig.vendor(from: id.rawValue) == id)
    }
}
