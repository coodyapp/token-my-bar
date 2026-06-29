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
