import Foundation
import Testing
@testable import TokenMyBarCore

private func tempStoreURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("token-my-bar-tests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("snapshots.json")
}

@Test func snapshotStoreRoundTripsSnapshots() async throws {
    let url = tempStoreURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = SnapshotStore(fileURL: url)

    let snapshots = [
        ProviderSnapshot(
            providerID: .codex,
            status: .ok,
            usedTokens: 1234,
            usagePercent: 42,
            resetAt: Date(timeIntervalSince1970: 1_700_000_000),
            refreshedAt: Date(timeIntervalSince1970: 1_700_000_500),
            primarySource: .oauth,
            confidence: .high,
            isEstimated: false,
            usageRows: [UsageRow(key: "session", title: "Session", value: "42%", percent: 42)]
        ),
    ]

    try await store.save(snapshots)
    let loaded = try await store.load()
    #expect(loaded == snapshots)
}

@Test func snapshotStoreLoadsEmptyWhenMissing() async throws {
    let url = tempStoreURL()
    let store = SnapshotStore(fileURL: url)
    let loaded = try await store.load()
    #expect(loaded.isEmpty)
}

@Test func snapshotStoreWritesRestrictivePermissions() async throws {
    let url = tempStoreURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = SnapshotStore(fileURL: url)

    try await store.save([])

    let filePerms = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
    #expect(filePerms?.int16Value == 0o600)

    let dirPerms = try FileManager.default.attributesOfItem(atPath: url.deletingLastPathComponent().path)[.posixPermissions] as? NSNumber
    #expect(dirPerms?.int16Value == 0o700)
}

@Test func snapshotStoreAtomicOverwriteKeepsLatest() async throws {
    let url = tempStoreURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = SnapshotStore(fileURL: url)

    try await store.save([ProviderSnapshot(providerID: .codex, status: .ok, usedTokens: 1, primarySource: .oauth, confidence: .high, isEstimated: false)])
    try await store.save([ProviderSnapshot(providerID: .opencode, status: .ok, usedTokens: 2, primarySource: .browserCookie, confidence: .high, isEstimated: false)])

    let loaded = try await store.load()
    #expect(loaded.count == 1)
    #expect(loaded.first?.providerID == .opencode)
}

@Test func snapshotStoreLoadsOnlyFreshCache() async throws {
    let url = tempStoreURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = SnapshotStore(fileURL: url)
    let snapshots = [ProviderSnapshot(providerID: .codex, status: .ok, usedTokens: nil, usagePercent: 10, primarySource: .oauth, confidence: .high, isEstimated: false)]

    try await store.save(snapshots)
    let modified = try #require(await store.modificationDate())
    let fresh = await store.loadIfFresh(ttl: 60, now: modified.addingTimeInterval(30))

    #expect(await store.isFresh(ttl: 60, now: modified.addingTimeInterval(30)))
    #expect(fresh?.first?.providerID == .codex)
    #expect(fresh?.first?.usagePercent == 10)
    #expect(await store.loadIfFresh(ttl: 60, now: modified.addingTimeInterval(61)) == nil)
}

@Test func snapshotStoreRefreshLockIsExclusive() async throws {
    let url = tempStoreURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let first = SnapshotStore(fileURL: url)
    let second = SnapshotStore(fileURL: url)

    #expect(await first.tryBeginRefresh())
    #expect(await second.tryBeginRefresh() == false)

    await first.endRefresh()
    #expect(await second.tryBeginRefresh())
    await second.endRefresh()
}
