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

@Test func appConfigVendorAliases() {
    #expect(AppConfig.vendor(from: "openai") == .codex)
    #expect(AppConfig.vendor(from: "claude-code") == .claudeCode)
    #expect(AppConfig.vendor(from: "open-code") == .opencode)
}
