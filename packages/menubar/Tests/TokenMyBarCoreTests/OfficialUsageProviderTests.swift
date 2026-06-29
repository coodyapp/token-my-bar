import Testing
@testable import TokenMyBarCore

@Test func codexOAuthSnapshotReadsRateLimitWindows() {
    // ChatGPT reports percent *remaining*; the provider inverts to *used* so
    // Codex counts up 0→100 like the other vendors (12.4% left → 87.6% used).
    let snapshot = CodexOAuthUsageProvider.snapshot(from: [
        "rate_limit": [
            "primary_window": ["usagePercent": 12.4, "resetInSec": 3600],
            "secondary_window": ["usagePercent": 3.0, "resetInSec": 86_400],
        ],
    ])

    #expect(snapshot.status == .ok)
    #expect(snapshot.primarySource == .oauth)
    #expect(snapshot.usagePercent == 87.6)
    #expect(snapshot.usageRows.map(\.key) == ["session", "weekly"])
    #expect(snapshot.usageRows.first?.value == "88%")
}

@Test func claudeOAuthSnapshotReadsExpectedWindows() {
    let snapshot = ClaudeOAuthUsageProvider.snapshot(from: [
        "five_hour": ["utilization": 29, "resetInSec": 4_320],
        "seven_day": ["utilization": 47, "resetInSec": 79_200],
        "seven_day_sonnet": ["utilization": 4],
        "extra_usage": ["is_enabled": true, "monthly_limit": 20_000, "used_credits": 7_788],
    ])

    #expect(snapshot.status == .ok)
    #expect(snapshot.providerID == .claudeCode)
    #expect(snapshot.usagePercent == 29)
    #expect(snapshot.usageRows.map(\.key) == ["session", "weekly", "sonnet", "extra-usage"])
}

@Test func opencodeCookieSnapshotReadsRollingWeeklyMonthly() {
    // Matches the OpenCode Go usage screen: Rolling 0%, Weekly 8%, Monthly 6%.
    let snapshot = OpenCodeCookieUsageProvider.snapshot(from: [
        "rollingUsage": ["usagePercent": 0, "resetInSec": 18_000],
        "weeklyUsage": ["usagePercent": 8, "resetInSec": 550_800],
        "monthlyUsage": ["usagePercent": 6, "resetInSec": 1_998_000],
    ])

    #expect(snapshot.status == .ok)
    #expect(snapshot.primarySource == .browserCookie)
    #expect(snapshot.usagePercent == 0)
    #expect(snapshot.usageRows.map(\.key) == ["rolling", "weekly", "monthly"])
    #expect(snapshot.usageRows.map(\.title) == ["Rolling Usage", "Weekly Usage", "Monthly Usage"])
    #expect(snapshot.usageRows[1].value == "8%")
}

@Test func claudeExtraUsageRowComputesSpendPercent() {
    // Screenshot: R$77.88 spent of R$200.00 limit => ~39% used.
    let row = ClaudeOAuthUsageProvider.extraUsageRow([
        "is_enabled": true,
        "monthly_limit": 20_000,
        "used_credits": 7_788,
    ])

    #expect(row?.value == "39%")
    #expect(row?.percent == 38.94)
    #expect(row?.subtitle == "This month: $77.88 / $200.00")
    #expect(row?.detail == "39% used")
}

@Test func claudeExtraUsageIgnoredWhenDisabled() {
    #expect(ClaudeOAuthUsageProvider.extraUsageRow(["is_enabled": false, "monthly_limit": 20_000, "used_credits": 100]) == nil)
    #expect(ClaudeOAuthUsageProvider.extraUsageRow(["monthly_limit": 0]) == nil)
}

@Test func claudeSnapshotUsesUtilizationAndResetsAt() {
    // Screenshot: session 100% used, weekly 18% used.
    let snapshot = ClaudeOAuthUsageProvider.snapshot(from: [
        "five_hour": ["utilization": 100, "resets_at": "2026-07-04T17:00:00Z"],
        "seven_day": ["utilization": 18, "resets_at": "2026-07-04T14:59:00Z"],
    ])

    #expect(snapshot.status == .ok)
    #expect(snapshot.usagePercent == 100)
    #expect(snapshot.usageRows.first?.value == "100%")
    #expect(snapshot.usageRows.map(\.key) == ["session", "weekly"])
}
