import Foundation
import Testing
@testable import TokenMyBarCore

private func mergeSnap(
    _ id: ProviderID,
    status: ProviderStatus,
    percent: Double? = nil,
    rows: [UsageRow] = []
) -> ProviderSnapshot {
    ProviderSnapshot(
        providerID: id,
        status: status,
        usedTokens: nil,
        usagePercent: percent,
        primarySource: .oauth,
        confidence: .high,
        isEstimated: false,
        usageRows: rows
    )
}

// MARK: - SnapshotMerger (A1)

@Test func mergeKeepsCachedAsStaleWhenFreshFailsAndCacheHasData() {
    let merged = SnapshotMerger.merge(
        fresh: [mergeSnap(.codex, status: .error)],
        cached: [mergeSnap(.codex, status: .ok, percent: 42)]
    )
    #expect(merged.first?.status == .stale)
    #expect(merged.first?.usagePercent == 42)
}

@Test func mergeReturnsFreshWhenOK() {
    let merged = SnapshotMerger.merge(
        fresh: [mergeSnap(.codex, status: .ok, percent: 10)],
        cached: [mergeSnap(.codex, status: .ok, percent: 99)]
    )
    #expect(merged.first?.status == .ok)
    #expect(merged.first?.usagePercent == 10)
}

@Test func mergeReturnsFreshFailureWhenNoCachedData() {
    let merged = SnapshotMerger.merge(
        fresh: [mergeSnap(.codex, status: .unauthenticated)],
        cached: []
    )
    #expect(merged.first?.status == .unauthenticated)
}

@Test func mergeIgnoresCachedWithoutUsableData() {
    // Cached snapshot has no percent/tokens/rows, so there's nothing to fall
    // back to — the fresh failure must be surfaced rather than a blank stale.
    let merged = SnapshotMerger.merge(
        fresh: [mergeSnap(.codex, status: .error)],
        cached: [mergeSnap(.codex, status: .ok)]
    )
    #expect(merged.first?.status == .error)
}

@Test func snapshotsToSaveReplacesStaleWithOriginalCached() {
    let cached = [mergeSnap(.codex, status: .ok, percent: 50)]
    let merged = SnapshotMerger.merge(fresh: [mergeSnap(.codex, status: .error)], cached: cached)
    // A transient failure must never overwrite good cached data on disk.
    let toSave = SnapshotMerger.snapshotsToSave(merged: merged, cached: cached)
    #expect(toSave.first?.status == .ok)
    #expect(toSave.first?.usagePercent == 50)
}

@Test func shouldUseCachedBucketsByStatus() {
    #expect(SnapshotMerger.shouldUseCached(for: mergeSnap(.codex, status: .error)))
    #expect(SnapshotMerger.shouldUseCached(for: mergeSnap(.codex, status: .unauthenticated)))
    #expect(SnapshotMerger.shouldUseCached(for: mergeSnap(.codex, status: .noData)))
    #expect(!SnapshotMerger.shouldUseCached(for: mergeSnap(.codex, status: .ok)))
    #expect(!SnapshotMerger.shouldUseCached(for: mergeSnap(.codex, status: .stale)))
    #expect(!SnapshotMerger.shouldUseCached(for: mergeSnap(.codex, status: .loading)))
}

// MARK: - ProviderSnapshot.failure mapping (A2)

@Test func failureMapsMissingCredentialsToUnauthenticated() {
    let s = ProviderSnapshot.failure(
        AuthError.missingCredentials, providerID: .codex, source: .oauth,
        authSummary: "Codex OAuth", missingMessage: "creds missing", failureMessage: "failed"
    )
    #expect(s.status == .unauthenticated)
    #expect(s.message == "creds missing")
}

@Test func failureMaps401And403ToUnauthenticated() {
    for code in [401, 403] {
        let s = ProviderSnapshot.failure(
            AuthError.http(code), providerID: .codex, source: .oauth,
            authSummary: "x", missingMessage: "m", failureMessage: "f"
        )
        #expect(s.status == .unauthenticated)
    }
}

@Test func failureMapsOtherHTTPStatusToErrorWithCode() {
    let s = ProviderSnapshot.failure(
        AuthError.http(500), providerID: .codex, source: .oauth,
        authSummary: "x", missingMessage: "m", failureMessage: "usage failed"
    )
    #expect(s.status == .error)
    #expect(s.message == "usage failed (HTTP 500)")
}

@Test func failureMapsUnknownErrorToGenericError() {
    struct Boom: Error {}
    let s = ProviderSnapshot.failure(
        Boom(), providerID: .codex, source: .oauth,
        authSummary: "x", missingMessage: "m", failureMessage: "usage failed"
    )
    #expect(s.status == .error)
    #expect(s.message == "usage failed")
}

// MARK: - OpenCode workspace id validation (S1)

@Test func workspaceIDValidationRejectsUnsafeOverrides() {
    #expect(OpenCodeCookieUsageProvider.isValidWorkspaceID("wrk_abc123"))
    #expect(OpenCodeCookieUsageProvider.isValidWorkspaceID("ABC_123"))
    #expect(!OpenCodeCookieUsageProvider.isValidWorkspaceID(""))
    #expect(!OpenCodeCookieUsageProvider.isValidWorkspaceID("../etc/passwd"))
    #expect(!OpenCodeCookieUsageProvider.isValidWorkspaceID("wrk?x=1"))
    #expect(!OpenCodeCookieUsageProvider.isValidWorkspaceID("wrk/go"))
    #expect(!OpenCodeCookieUsageProvider.isValidWorkspaceID("wrk abc"))
}
