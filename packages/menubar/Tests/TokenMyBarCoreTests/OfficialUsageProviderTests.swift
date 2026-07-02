import Foundation
import Testing
@testable import TokenMyBarCore

@Test func codexOAuthSnapshotReadsRateLimitWindows() {
    // Real /backend-api/wham/usage shape (verified 2026-07-01): used_percent
    // is already percent *used*; reset_after_seconds is the static window
    // length, reset_at the actual reset moment.
    let snapshot = CodexOAuthUsageProvider.snapshot(from: [
        "plan_type": "plus",
        "rate_limit": [
            "primary_window": [
                "used_percent": 1,
                "limit_window_seconds": 18_000,
                "reset_after_seconds": 18_000,
                "reset_at": 1_782_975_710,
            ],
            "secondary_window": [
                "used_percent": 0,
                "limit_window_seconds": 604_800,
                "reset_after_seconds": 604_800,
                "reset_at": 1_783_562_510,
            ],
        ],
    ])

    #expect(snapshot.status == .ok)
    #expect(snapshot.primarySource == .oauth)
    #expect(snapshot.usagePercent == 1)
    #expect(snapshot.usageRows.map(\.key) == ["session", "weekly"])
    #expect(snapshot.usageRows.map(\.value) == ["1%", "0%"])
    #expect(snapshot.planName == "Plus")
    #expect(snapshot.resetAt == Date(timeIntervalSince1970: 1_782_975_710))
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
    // Usage is always parsed off the Go workspace page, so the plan badge
    // defaults to "Go" when the page carries no explicit plan field.
    #expect(snapshot.planName == "Go")
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

@Test func claudePlanFromKeychainPayloadReadsSubscriptionType() {
    let payload: [String: Any] = [
        "claudeAiOauth": ["accessToken": "tok", "subscriptionType": "pro"],
    ]
    #expect(ClaudeOAuthUsageProvider.planFromKeychainPayload(payload) == "Pro")
    #expect(ClaudeOAuthUsageProvider.planFromKeychainPayload(["access_token": "flat"]) == nil)
}

@Test func claudeSnapshotUsesFallbackPlanWhenResponseHasNone() {
    // The OAuth usage response carries no plan field; the badge comes from the
    // stored credential's subscriptionType.
    let snapshot = ClaudeOAuthUsageProvider.snapshot(
        from: ["five_hour": ["utilization": 10, "resets_at": "2026-07-02T03:10:00Z"]],
        fallbackPlanName: "Pro"
    )
    #expect(snapshot.planName == "Pro")
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
