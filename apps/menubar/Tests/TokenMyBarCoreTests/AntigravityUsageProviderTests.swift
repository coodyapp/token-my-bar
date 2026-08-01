import Foundation
import Testing
@testable import TokenMyBarCore

/// Recorded from the live `v1internal:retrieveUserQuota` response.
private func liveQuota() -> [String: Any] {
    [
        "buckets": [
            ["resetTime": "2026-08-02T20:28:34Z", "tokenType": "REQUESTS", "modelId": "gemini-2.5-flash", "remainingFraction": 1],
            ["resetTime": "2026-08-02T20:28:34Z", "tokenType": "REQUESTS", "modelId": "gemini-2.5-pro", "remainingFraction": 0.25],
            ["resetTime": "2026-08-02T20:28:34Z", "tokenType": "REQUESTS", "modelId": "gemini-3.1-flash-lite", "remainingFraction": 0],
        ],
    ]
}

@Test func antigravityInvertsRemainingFractionIntoPercentUsed() {
    // The vendor reports what is LEFT on a 0...1 scale — the inverse of every
    // other provider. Reading it as "used" would show a full quota as exhausted.
    #expect(AntigravityUsageProvider.usedPercent(in: ["remainingFraction": 1]) == 0)
    #expect(AntigravityUsageProvider.usedPercent(in: ["remainingFraction": 0.25]) == 75)
    #expect(AntigravityUsageProvider.usedPercent(in: ["remainingFraction": 0]) == 100)
    #expect(AntigravityUsageProvider.usedPercent(in: ["other": 1]) == nil)
    #expect(AntigravityUsageProvider.usedPercent(in: ["remainingFraction": Double.nan]) == nil)
}

@Test func antigravitySnapshotLeadsWithTheModelClosestToItsCap() {
    let snapshot = AntigravityUsageProvider.snapshot(from: liveQuota(), tier: "Standard")

    #expect(snapshot.status == .ok)
    #expect(snapshot.providerID == .antigravity)
    // Worst bucket drives the headline, so a single exhausted model is visible.
    #expect(snapshot.usagePercent == 100)
    #expect(snapshot.usageRows.map(\.percent) == [100, 75, 0])
    #expect(snapshot.usageRows.first?.title == "Gemini 3.1 Flash Lite")
    #expect(snapshot.planName == "Standard")
    #expect(snapshot.usageRows.allSatisfy { $0.resetAt != nil })
}

@Test func antigravityReportsNoDataRatherThanZeroWhenBucketsAreMissing() {
    let snapshot = AntigravityUsageProvider.snapshot(from: [:])

    #expect(snapshot.status == .noData)
    #expect(snapshot.usagePercent == nil)
    #expect(snapshot.usageRows.isEmpty)
}

@Test func antigravityWarnsOnceTheSignInHasLapsed() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    #expect(AntigravityUsageProvider.expiryNotice(now.addingTimeInterval(3600), now: now) == nil)
    #expect(AntigravityUsageProvider.expiryNotice(now.addingTimeInterval(-60), now: now)?.contains("expired") == true)
    #expect(AntigravityUsageProvider.expiryNotice(nil, now: now) == nil)
}

@Test func antigravityTierNamePrefersTheDefaultTier() {
    // Shape recorded from the live loadCodeAssist response.
    let payload: [String: Any] = [
        "allowedTiers": [
            ["id": "free-tier", "name": "Gemini Code Assist for individuals", "isDefault": false],
            ["id": "standard-tier", "name": "Gemini Code Assist", "isDefault": true],
        ],
    ]

    #expect(AntigravityUsageProvider.tierName(in: payload) == "Standard")
    #expect(AntigravityUsageProvider.tierName(in: [:]) == nil)
}

@Test func antigravityModelTitlesStayReadable() {
    #expect(AntigravityUsageProvider.modelTitle("gemini-2.5-flash-lite") == "Gemini 2.5 Flash Lite")
    #expect(AntigravityUsageProvider.modelTitle("gemini-3.1-flash-lite") == "Gemini 3.1 Flash Lite")
}

@Test func antigravityShowsOnlyGeminiModels() {
    // Antigravity meters its Claude and GPT models as a separate group with its
    // own limits; listing them beside Gemini reads as one pool that they are not.
    let mixed: [String: Any] = ["buckets": [
        ["modelId": "gemini-2.5-pro", "remainingFraction": 0.5, "resetTime": "2026-08-02T20:28:34Z"],
        ["modelId": "claude-sonnet-4-5", "remainingFraction": 0.1, "resetTime": "2026-08-02T20:28:34Z"],
        ["modelId": "gpt-oss-120b", "remainingFraction": 0, "resetTime": "2026-08-02T20:28:34Z"],
    ]]

    let snapshot = AntigravityUsageProvider.snapshot(from: mixed)

    #expect(snapshot.usageRows.map(\.title) == ["Gemini 2.5 Pro"])
    // The headline must come from the models shown, not the ones filtered out.
    #expect(snapshot.usagePercent == 50)
}
