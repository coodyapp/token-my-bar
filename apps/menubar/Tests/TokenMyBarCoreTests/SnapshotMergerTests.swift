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

@Test func resolveKeepsCachedAsStaleWhenFreshFailsAndCacheHasData() {
    let taken = Date(timeIntervalSince1970: 1000)
    let cached = ProviderSnapshot(
        providerID: .codex, status: .ok, usedTokens: nil, usagePercent: 42,
        refreshedAt: taken, primarySource: .oauth, confidence: .high, isEstimated: false
    )
    let resolved = SnapshotMerger.resolve(fresh: [mergeSnap(.codex, status: .error)], cached: [cached])

    #expect(resolved.display.first?.status == .stale)
    #expect(resolved.display.first?.usagePercent == 42)
    // A transient failure must never destroy good cached numbers — but what lands
    // on disk is what is shown, so a cache reader (CLI, Waybar, the next launch)
    // sees the same "stale" state instead of a healthy-looking "ok".
    #expect(resolved.persist.first?.status == .stale)
    #expect(resolved.persist.first?.usagePercent == 42)
    // Re-presented numbers keep the time they were actually taken.
    #expect(resolved.persist.first?.refreshedAt == taken)
    #expect(resolved.display.first?.refreshedAt == taken)
}

@Test func resolveReturnsFreshWhenOK() {
    let resolved = SnapshotMerger.resolve(
        fresh: [mergeSnap(.codex, status: .ok, percent: 10)],
        cached: [mergeSnap(.codex, status: .ok, percent: 99)]
    )
    #expect(resolved.display.first?.usagePercent == 10)
    #expect(resolved.persist.first?.usagePercent == 10)
}

@Test func resolveReturnsFreshFailureWhenNoCachedData() {
    let resolved = SnapshotMerger.resolve(
        fresh: [mergeSnap(.codex, status: .unauthenticated)],
        cached: []
    )
    #expect(resolved.display.first?.status == .unauthenticated)
    #expect(resolved.persist.first?.status == .unauthenticated)
}

@Test func resolvePersistsFreshDataWhenTheFailedSnapshotStillCarriesUsage() {
    // The local-log fallback keeps producing current rows after the OAuth token
    // expires. Showing the older cache would present days-old numbers as if they
    // were current — and persisting it instead would freeze the cache there, so
    // the CLI and Waybar would serve pre-expiry numbers as healthy forever.
    let fresh = mergeSnap(.claudeCode, status: .unauthenticated, rows: [
        UsageRow(key: "session", title: "Session", value: "1.2M"),
    ])
    let resolved = SnapshotMerger.resolve(fresh: [fresh], cached: [mergeSnap(.claudeCode, status: .ok, percent: 42)])

    #expect(resolved.display.first?.status == .unauthenticated)
    #expect(resolved.display.first?.usageRows.first?.value == "1.2M")
    #expect(resolved.persist.first?.usageRows.first?.value == "1.2M")
    #expect(resolved.persist.first?.usagePercent == nil)
}

@Test func resolveKeepsSignInSignalWhenFallingBackToCache() {
    // Expired auth must not be laundered into a plain "Stale" badge: the user
    // needs to see that re-authentication — not just a retry — is required.
    let resolved = SnapshotMerger.resolve(
        fresh: [mergeSnap(.claudeCode, status: .unauthenticated)],
        cached: [mergeSnap(.claudeCode, status: .ok, percent: 42)]
    )

    #expect(resolved.display.first?.status == .unauthenticated)
    #expect(resolved.display.first?.usagePercent == 42)
    #expect(resolved.display.first?.message?.isEmpty == false)
    // The cache carries the same signal, so `token-my-bar --json` reports class
    // "unauthenticated" rather than "normal" at a percent nobody can refresh.
    #expect(resolved.persist.first?.status == .unauthenticated)
    #expect(resolved.persist.first?.usagePercent == 42)
}

@Test func resolveKeepsSignInSignalThroughAnUnrelatedFailure() {
    // Once "sign in" is recorded, a dropped network or a vendor 500 (both .error)
    // must not downgrade it to "stale": the token is still expired, and the cache
    // is what a cold start and `token-my-bar --json` now report.
    let cached = ProviderSnapshot(
        providerID: .claudeCode, status: .unauthenticated, usedTokens: nil, usagePercent: 42,
        primarySource: .oauth, confidence: .high, isEstimated: false,
        message: "Sign in again; showing cached data"
    )
    let resolved = SnapshotMerger.resolve(fresh: [mergeSnap(.claudeCode, status: .error)], cached: [cached])

    #expect(resolved.display.first?.status == .unauthenticated)
    #expect(resolved.persist.first?.status == .unauthenticated)
    #expect(resolved.display.first?.usagePercent == 42)
    #expect(resolved.display.first?.message == "Sign in again; showing cached data")
}

@Test func resolveIgnoresCachedWithoutUsableData() {
    // Cached snapshot has no percent/tokens/rows, so there's nothing to fall
    // back to — the fresh failure must be surfaced rather than a blank stale.
    let resolved = SnapshotMerger.resolve(
        fresh: [mergeSnap(.codex, status: .error)],
        cached: [mergeSnap(.codex, status: .ok)]
    )
    #expect(resolved.display.first?.status == .error)
}

@Test func resolveKeepsCachedProvidersAbsentFromRefresh() {
    // A subset refresh (e.g. only claude-code enabled) must not wipe other
    // vendors' last-good data from the shared on-disk cache that the CLI and
    // other instances read without an enabled filter.
    let cached = [
        mergeSnap(.claudeCode, status: .ok, percent: 10),
        mergeSnap(.codex, status: .ok, percent: 50),
    ]
    let resolved = SnapshotMerger.resolve(fresh: [mergeSnap(.claudeCode, status: .ok, percent: 20)], cached: cached)

    #expect(resolved.persist.count == 2)
    #expect(resolved.persist.contains { $0.providerID == .codex && $0.usagePercent == 50 })
    #expect(resolved.persist.contains { $0.providerID == .claudeCode && $0.usagePercent == 20 })
    // Persisted order is canonical (codex, claude-code, opencode) regardless of
    // which subset refreshed, so cache readers see one stable vendor order.
    #expect(resolved.persist.map(\.providerID) == [.codex, .claudeCode])
    #expect(resolved.display.map(\.providerID) == [.claudeCode])
}

@Test func resolveDoesNotFreezeTheCacheAcrossRepeatedFailures() {
    // Feeding a resolution's own output back in is what every refresh does while
    // a token stays expired; the persisted numbers have to keep advancing.
    func fallbackSnapshot(session: String) -> ProviderSnapshot {
        mergeSnap(.claudeCode, status: .unauthenticated, rows: [
            UsageRow(key: "session", title: "Session", value: session),
        ])
    }

    var cache = [mergeSnap(.claudeCode, status: .ok, percent: 42)]
    cache = SnapshotMerger.resolve(fresh: [fallbackSnapshot(session: "1.2M")], cached: cache).persist
    cache = SnapshotMerger.resolve(fresh: [fallbackSnapshot(session: "1.5M")], cached: cache).persist

    #expect(cache.first?.usageRows.first?.value == "1.5M")
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
