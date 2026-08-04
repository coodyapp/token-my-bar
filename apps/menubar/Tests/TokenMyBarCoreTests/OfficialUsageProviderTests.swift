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

@Test func claudeOAuthReadsTheLimitsArrayIncludingPerModelCaps() {
    // Recorded from the live payload of a Max 5x account: the top-level
    // seven_day_* keys are all null and every real window — including the
    // per-model "Fable" cap the usage screen shows — lives in `limits`.
    let snapshot = ClaudeOAuthUsageProvider.snapshot(from: [
        "five_hour": ["utilization": 43.0, "resets_at": "2026-08-02T00:10:00.084152+00:00"],
        "seven_day": ["utilization": 4.0, "resets_at": "2026-08-08T18:00:00.084173+00:00"],
        "seven_day_sonnet": NSNull(),
        "limits": [
            ["kind": "session", "group": "session", "percent": 43, "resets_at": "2026-08-02T00:10:00.084152+00:00"],
            ["kind": "weekly_all", "group": "weekly", "percent": 4, "resets_at": "2026-08-08T18:00:00.084173+00:00"],
            ["kind": "weekly_scoped", "group": "weekly", "percent": 0, "resets_at": NSNull(),
             "scope": ["model": ["display_name": "Fable"]]],
        ],
    ])

    #expect(snapshot.status == .ok)
    #expect(snapshot.usageRows.map(\.title) == ["Session", "Weekly", "Fable only"])
    #expect(snapshot.usageRows.map(\.percent) == [43, 4, 0])
    // Microsecond-precision timestamps must still parse into a reset date.
    #expect(snapshot.usageRows[0].resetAt != nil)
    #expect(snapshot.usageRows[1].resetAt != nil)
}

@Test func claudePlanBadgeUsesTheRateLimitTier() {
    // The same account reports subscriptionType "max" and rateLimitTier
    // "default_claude_max_5x"; the tier is what the percentages are a share of.
    let payload: [String: Any] = ["claudeAiOauth": [
        "subscriptionType": "max",
        "rateLimitTier": "default_claude_max_5x",
    ]]

    #expect(ClaudeOAuthUsageProvider.planFromKeychainPayload(payload) == "Max 5x")
    #expect(ClaudeOAuthUsageProvider.planFromKeychainPayload(["claudeAiOauth": ["subscriptionType": "pro"]]) == "Pro")
}

@Test func codexNamesTheWindowByItsRealLength() {
    // A Plus account's `primary_window` is a 7-day window; calling it "Session"
    // is how a spent week reads as a quiet afternoon.
    let snapshot = CodexOAuthUsageProvider.snapshot(from: [
        "plan_type": "plus",
        "rate_limit": [
            "primary_window": ["used_percent": 0, "limit_window_seconds": 604_800, "reset_at": 1_786_221_052],
            "secondary_window": NSNull(),
        ],
    ])

    #expect(snapshot.planName == "Plus")
    #expect(snapshot.usageRows.map(\.title) == ["Weekly"])
    #expect(snapshot.usageRows.first?.resetAt == Date(timeIntervalSince1970: 1_786_221_052))
    // A genuine 5-hour window still reads as the session.
    let session = CodexOAuthUsageProvider.windowRow(["used_percent": 12, "limit_window_seconds": 18_000], fallbackKey: "weekly")
    #expect(session.title == "Session")
}

@Test func claudeOAuthSnapshotReadsExpectedWindows() {
    // Per-model weekly caps are enumerated, not listed by name: the live account
    // that shows "Fable" alongside "All models" proved a hardcoded sonnet/opus
    // list drops whatever model the plan gains next.
    let snapshot = ClaudeOAuthUsageProvider.snapshot(from: [
        "five_hour": ["utilization": 29, "resetInSec": 4_320],
        "seven_day": ["utilization": 47, "resetInSec": 79_200],
        "seven_day_sonnet": ["utilization": 4],
        "seven_day_fable": ["utilization": 0],
        "extra_usage": ["is_enabled": true, "monthly_limit": 20_000, "used_credits": 7_788],
    ])

    #expect(snapshot.status == .ok)
    #expect(snapshot.providerID == .claudeCode)
    #expect(snapshot.usagePercent == 29)
    #expect(snapshot.usageRows.map(\.key) == ["session", "weekly", "seven_day_fable", "seven_day_sonnet", "extra-usage"])
    #expect(snapshot.usageRows.map(\.title) == ["Session", "Weekly", "Fable only", "Sonnet only", "Extra usage"])
}

@Test func claudeOAuthSnapshotReportsARenamedPercentFieldAsAnError() {
    // A field rename must not read as "0% used" — that tells the user they have a
    // full tank when the window may be spent.
    let snapshot = ClaudeOAuthUsageProvider.snapshot(from: [
        "five_hour": ["utilization_pct": 29, "resetInSec": 4_320],
    ])

    #expect(snapshot.status == .error)
    #expect(snapshot.message?.contains("Session") == true)
    #expect(snapshot.usageRows.first?.percent == nil)
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

@Test func claudeExtraUsageRejectsNonFiniteValuesInsteadOfTrapping() {
    // NaN survives min/max clamping (all comparisons are false), so an
    // unguarded Int(percent.rounded()) traps. Unreadable values read as absent.
    let nanUsed = ClaudeOAuthUsageProvider.extraUsageRow([
        "is_enabled": true, "monthly_limit": 20_000, "used_credits": "nan",
    ])
    #expect(nanUsed?.value == "0%")

    // inf/inf = NaN inside the percent math; an infinite limit is no limit.
    #expect(ClaudeOAuthUsageProvider.extraUsageRow([
        "is_enabled": true, "monthly_limit": "inf", "used_credits": "inf",
    ]) == nil)

    let negative = ClaudeOAuthUsageProvider.extraUsageRow([
        "is_enabled": true, "monthly_limit": 20_000, "used_credits": -500,
    ])
    #expect(negative?.value == "0%")

    let huge = ClaudeOAuthUsageProvider.extraUsageRow([
        "is_enabled": true, "monthly_limit": 20_000, "used_credits": 1e18,
    ])
    #expect(huge?.value == "100%")
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
