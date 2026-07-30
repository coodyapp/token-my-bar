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

@Test func appConfigVendorAliases() {
    #expect(AppConfig.vendor(from: "openai") == .codex)
    #expect(AppConfig.vendor(from: "claude-code") == .claudeCode)
    #expect(AppConfig.vendor(from: "open-code") == .opencode)
}
