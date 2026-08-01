import Foundation
import Testing
@testable import TokenMyBarCore

/// Trimmed from a live GetUserStatus response: models that share an allowance
/// report the identical remainingFraction and resetTime, which is what makes
/// them a group.
private func liveStatus() -> [String: Any] {
    [
        "email": "someone@example.com",
        "planStatus": ["planInfo": ["planName": "Pro", "teamsTier": "TEAMS_TIER_PRO"]],
        "cascadeModelConfigData": ["clientModelConfigs": [
            ["modelId": "gemini-3.6-flash-medium", "label": "Gemini 3.6 Flash (Medium)",
             "quotaInfo": ["remainingFraction": 0.9830696, "resetTime": "2026-08-02T01:14:49Z"]],
            ["modelId": "gemini-3.1-pro-low", "label": "Gemini 3.1 Pro (Low)",
             "quotaInfo": ["remainingFraction": 0.9830696, "resetTime": "2026-08-02T01:14:49Z"]],
            ["modelId": "claude-sonnet-4-6", "label": "Claude Sonnet 4.6",
             "quotaInfo": ["remainingFraction": 1, "resetTime": "2026-08-02T02:28:52Z"]],
            ["modelId": "gpt-oss-120b-medium", "label": "GPT-OSS 120B",
             "quotaInfo": ["remainingFraction": 1, "resetTime": "2026-08-02T02:28:52Z"]],
        ]],
    ]
}

@Test func antigravityLocalCollapsesTheGeminiGroupIntoOneRow() {
    // The vendor's own screen shows one figure per group. Listing each model
    // repeats a single number under a dozen names and reads as a dozen pools.
    let snapshot = AntigravityLocalUsageProvider.snapshot(from: liveStatus())

    #expect(snapshot.status == .ok)
    #expect(snapshot.usageRows.count == 1)
    #expect(snapshot.usageRows.first?.title == "Gemini models")
    // 0.9830696 remaining is 1.69% used — not 98%.
    #expect(snapshot.usageRows.first?.value == "2%")
    #expect(snapshot.usagePercent.map { ($0 * 100).rounded() / 100 } == 1.69)
    #expect(snapshot.usageRows.first?.resetAt == RemoteJSON.parseISO8601("2026-08-02T01:14:49Z"))
}

@Test func antigravityLocalExcludesClaudeAndGPTModels() {
    // They are metered against a separate allowance with its own reset.
    let rows = AntigravityLocalUsageProvider.rows(from: liveStatus())

    #expect(rows.count == 1)
    #expect(!rows.contains { $0.title.lowercased().contains("claude") || $0.title.lowercased().contains("gpt") })
}

@Test func antigravityLocalReadsThePlanFromTheServer() {
    // "Pro" is the Antigravity plan; the OAuth path reported the unrelated
    // Gemini Code Assist tier instead.
    #expect(AntigravityLocalUsageProvider.snapshot(from: liveStatus()).planName == "Pro")
}

@Test func antigravityLocalReportsNoDataWhenTheServerKnowsNoQuota() {
    let snapshot = AntigravityLocalUsageProvider.snapshot(from: ["planStatus": ["planInfo": ["planName": "Pro"]]])

    #expect(snapshot.status == .noData)
    #expect(snapshot.usageRows.isEmpty)
}

@Test func antigravityLocalParsesListeningPortsFromLsofOutput() {
    // lsof puts the address before a trailing "(LISTEN)", so the port is the
    // last colon-separated number rather than the last field.
    let sample = """
    agy       57619 augustobrito   11u  IPv4 0xb17d856c65fb8f98      0t0  TCP 127.0.0.1:53613 (LISTEN)
    Antigravity 900 augustobrito   12u  IPv6 0x1                     0t0  TCP [::1]:54006 (LISTEN)
    ssh       123 augustobrito    3u  IPv4 0x2                       0t0  TCP 127.0.0.1:22 (LISTEN)
    """

    #expect(AntigravityLocalUsageProvider.ports(inLsofOutput: sample) == [53613, 54006])
}

@Test func antigravityLocalFailsFastWhenNothingIsListening() async {
    // Antigravity being closed is the normal case, and it must hand over to the
    // OAuth fallback quickly rather than stalling a refresh.
    let provider = AntigravityLocalUsageProvider(portFinder: { [] })
    let started = Date()

    let snapshot = await provider.snapshot()

    #expect(snapshot.status == .unauthenticated)
    #expect(snapshot.message?.contains("not running") == true)
    #expect(Date().timeIntervalSince(started) < 1)
}
