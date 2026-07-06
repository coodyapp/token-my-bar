import Testing
@testable import TokenMyBarCore

@Test func summarySelectionPrefersPrimaryElseFallsBackToFirst() {
    struct Seg: Equatable { let providerID: ProviderID }
    let segments = [Seg(providerID: .claudeCode), Seg(providerID: .codex)]

    // Primary configured and present -> that segment.
    #expect(SummarySelection.selected(segments, primary: .codex, id: \.providerID) == Seg(providerID: .codex))
    // No primary configured (the default) -> first segment, NOT nil/"--".
    #expect(SummarySelection.selected(segments, primary: nil, id: \.providerID) == Seg(providerID: .claudeCode))
    // Primary configured but absent from segments -> first segment.
    #expect(SummarySelection.selected(segments, primary: .opencode, id: \.providerID) == Seg(providerID: .claudeCode))
    // No usable segments -> nil.
    #expect(SummarySelection.selected([Seg](), primary: nil, id: \.providerID) == nil)
}

@Test func combinedStatusUsesHighestPercent() {
    let snapshots = [
        ProviderSnapshot(
            providerID: .codex,
            status: .ok,
            usedTokens: 100,
            usagePercent: 25,
            primarySource: .localLog,
            confidence: .medium,
            isEstimated: true
        ),
        ProviderSnapshot(
            providerID: .claudeCode,
            status: .ok,
            usedTokens: 200,
            usagePercent: 75,
            primarySource: .localLog,
            confidence: .medium,
            isEstimated: true
        ),
    ]

    let status = CombinedStatusFormatter.format(snapshots)

    #expect(status.title == "25% | 75%")
    #expect(status.snapshot?.providerID == .codex)
}

@Test func combinedStatusDoesNotPretendLocalTokensAreQuota() {
    let snapshots = [
        ProviderSnapshot(
            providerID: .opencode,
            status: .ok,
            usedTokens: 12_400,
            primarySource: .localLog,
            confidence: .medium,
            isEstimated: true
        ),
    ]

    let status = CombinedStatusFormatter.format(snapshots)

    #expect(status.title == "--")
}

@Test func combinedStatusShowsUnknownWithoutData() {
    let status = CombinedStatusFormatter.format([])

    #expect(status.title == "--")
}

@Test func combinedStatusUsesPrimaryVendorWhenConfigured() {
    let snapshots = [
        ProviderSnapshot(
            providerID: .codex,
            status: .ok,
            usedTokens: nil,
            usagePercent: 40,
            primarySource: .oauth,
            confidence: .high,
            isEstimated: false
        ),
        ProviderSnapshot(
            providerID: .opencode,
            status: .ok,
            usedTokens: nil,
            usagePercent: 90,
            primarySource: .browserCookie,
            confidence: .high,
            isEstimated: false
        ),
    ]

    let status = CombinedStatusFormatter.format(snapshots, primary: .codex)

    #expect(status.title == "40% | 90%")
    #expect(status.snapshot?.providerID == .codex)
}

@Test func combinedStatusFallsBackWhenPrimaryHasNoPercent() {
    let snapshots = [
        ProviderSnapshot(
            providerID: .codex,
            status: .ok,
            usedTokens: 12_000,
            primarySource: .localLog,
            confidence: .medium,
            isEstimated: true
        ),
        ProviderSnapshot(
            providerID: .opencode,
            status: .ok,
            usedTokens: nil,
            usagePercent: 90,
            primarySource: .browserCookie,
            confidence: .high,
            isEstimated: false
        ),
    ]

    let status = CombinedStatusFormatter.format(snapshots, primary: .codex)

    #expect(status.title == "90%")
    #expect(status.snapshot?.providerID == .opencode)
}
