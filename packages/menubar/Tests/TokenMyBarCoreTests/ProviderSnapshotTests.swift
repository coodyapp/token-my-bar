import Foundation
import Testing
@testable import TokenMyBarCore

@Test func staleCopyPreservesDataAndForcesStale() {
    let original = ProviderSnapshot(
        providerID: .claudeCode,
        status: .ok,
        usedTokens: 100,
        limitTokens: 500,
        usagePercent: 47,
        resetAt: Date(timeIntervalSince1970: 1000),
        primarySource: .oauth,
        sources: [.oauth, .api],
        confidence: .high,
        isEstimated: false,
        message: "fresh",
        authSummary: "Claude OAuth",
        usageRows: [UsageRow(key: "session", title: "Session", value: "47%", percent: 47)]
    )

    let when = Date(timeIntervalSince1970: 5000)
    let stale = original.staleCopy(refreshedAt: when)

    #expect(stale.status == .stale)
    #expect(stale.usagePercent == 47)
    #expect(stale.usedTokens == 100)
    #expect(stale.limitTokens == 500)
    #expect(stale.resetAt == original.resetAt)
    #expect(stale.usageRows == original.usageRows)
    #expect(stale.sources == original.sources)
    #expect(stale.message == "fresh")
    #expect(stale.refreshedAt == when)

    let withMessage = original.staleCopy(message: "cached", refreshedAt: when)
    #expect(withMessage.message == "cached")
}

@Test func usageSeverityBucketsByPercent() {
    #expect(UsageSeverity(percent: nil) == .normal)
    #expect(UsageSeverity(percent: 0) == .normal)
    #expect(UsageSeverity(percent: 69.9) == .normal)
    #expect(UsageSeverity(percent: 70) == .warning)
    #expect(UsageSeverity(percent: 89.9) == .warning)
    #expect(UsageSeverity(percent: 90) == .critical)
    #expect(UsageSeverity(percent: 100) == .critical)
}
