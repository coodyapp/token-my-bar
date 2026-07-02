import Foundation
import Testing
@testable import TokenMyBarCore

private struct SlowProvider: ProviderClient {
    let providerID: ProviderID = .codex

    func snapshot() async -> ProviderSnapshot {
        try? await Task.sleep(nanoseconds: 10_000_000_000)
        return ProviderSnapshot(
            providerID: providerID,
            status: .ok,
            usedTokens: nil,
            usagePercent: 99,
            primarySource: .oauth,
            confidence: .high,
            isEstimated: false
        )
    }
}

@Test func usageRefresherTimesOutSlowProvider() async throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("token-my-bar-tests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("snapshots.json")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let refresher = UsageRefresher(
        registry: ProviderRegistry(providers: [SlowProvider()]),
        store: SnapshotStore(fileURL: url),
        providerTimeout: 0.01
    )

    let snapshots = await refresher.refresh(ttl: 0)

    #expect(snapshots.count == 1)
    #expect(snapshots.first?.providerID == .codex)
    #expect(snapshots.first?.status == .error)
    #expect(snapshots.first?.message == "Vendor refresh timed out after 0.01s")
}

private struct FixedProvider: ProviderClient {
    let providerID: ProviderID = .codex
    let percent: Double

    func snapshot() async -> ProviderSnapshot {
        ProviderSnapshot(
            providerID: providerID,
            status: .ok,
            usedTokens: nil,
            usagePercent: percent,
            primarySource: .oauth,
            confidence: .high,
            isEstimated: false
        )
    }
}

private func tempSnapshotURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("token-my-bar-tests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("snapshots.json")
}

@Test func refreshReturnsCacheWithinTTLWithoutFetching() async throws {
    let url = tempSnapshotURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let store = SnapshotStore(fileURL: url)
    try await store.save([
        ProviderSnapshot(providerID: .codex, status: .ok, usedTokens: nil, usagePercent: 11, primarySource: .oauth, confidence: .high, isEstimated: false),
    ])

    let refresher = UsageRefresher(
        registry: ProviderRegistry(providers: [FixedProvider(percent: 77)]),
        store: store
    )
    let result = await refresher.refresh(ttl: 3600)

    // Fresh cache → the provider (77) is never consulted.
    #expect(result.first?.usagePercent == 11)
}

@Test func refreshReturnsCacheWhenAnotherInstanceHoldsLock() async throws {
    let url = tempSnapshotURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let store = SnapshotStore(fileURL: url)
    try await store.save([
        ProviderSnapshot(providerID: .codex, status: .ok, usedTokens: nil, usagePercent: 11, primarySource: .oauth, confidence: .high, isEstimated: false),
    ])

    // Simulate another instance holding the cross-process refresh lock.
    #expect(await store.tryBeginRefresh())
    defer { Task { await store.endRefresh() } }

    let refresher = UsageRefresher(
        registry: ProviderRegistry(providers: [FixedProvider(percent: 77)]),
        store: store
    )
    let result = await refresher.refresh(ttl: 0)

    // Lock unavailable → return cached, don't fetch (would have been 77).
    #expect(result.first?.usagePercent == 11)
}
