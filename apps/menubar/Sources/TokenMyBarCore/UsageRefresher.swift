import Foundation

/// Coordinates provider refreshes with a shared on-disk cache.
///
/// Refresh policy (cross-process safe):
/// 1. If the cache is younger than `ttl`, return it without touching any API.
/// 2. Otherwise acquire a non-blocking exclusive lock on the cache:
///    - lock acquired → re-check freshness, then fetch enabled providers,
///      merge with the previous cache, and persist atomically.
///    - lock unavailable (another instance is refreshing) → return the cache.
///
/// This lets multiple Waybar instances across monitors share one refresh and
/// avoid API stampedes.
public actor UsageRefresher {
    private let registry: ProviderRegistry
    private let store: SnapshotStore
    private let providerTimeout: TimeInterval

    public init(
        registry: ProviderRegistry = ProviderRegistry(),
        store: SnapshotStore = SnapshotStore(),
        providerTimeout: TimeInterval = 20
    ) {
        self.registry = registry
        self.store = store
        self.providerTimeout = providerTimeout
    }

    public func cached() async -> [ProviderSnapshot] {
        (try? await store.load()) ?? []
    }

    @discardableResult
    public func refresh(
        enabled: [ProviderID]? = nil,
        ttl: TimeInterval = 0,
        now: Date = Date()
    ) async -> [ProviderSnapshot] {
        if let fresh = await store.loadIfFresh(ttl: ttl, now: now) {
            return fresh
        }

        let enabledIDs = enabled ?? ProviderID.allCases
        let providers = registry.providers.filter { enabledIDs.contains($0.providerID) }
        let previous = (try? await store.load()) ?? []

        // Single-flight across processes: only the lock holder fetches.
        guard await store.tryBeginRefresh() else {
            Log.refresh.debug("refresh skipped: another instance holds the lock")
            return previous
        }
        // Release the lock synchronously before returning (no detached Task, so
        // the lock is always freed by the time refresh() returns).
        let merged = await fetchAndMerge(providers: providers, previous: previous, ttl: ttl, now: now)
        await store.endRefresh()
        return merged
    }

    /// Runs under the refresh lock: re-checks freshness, fetches enabled
    /// providers, merges with the previous cache, and persists atomically.
    private func fetchAndMerge(
        providers: [any ProviderClient],
        previous: [ProviderSnapshot],
        ttl: TimeInterval,
        now: Date
    ) async -> [ProviderSnapshot] {
        if let fresh = await store.loadIfFresh(ttl: ttl, now: now) {
            return fresh
        }

        let unordered = await withTaskGroup(of: ProviderSnapshot.self) { group in
            for provider in providers {
                group.addTask { await self.snapshot(for: provider) }
            }
            var collected: [ProviderSnapshot] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        // Task-group completion order is a network race, not a stable order;
        // callers (CLI --json/--verbose, menu bar popover) need one fixed
        // vendor order across runs instead of one that shuffles per refresh.
        let order = Dictionary(uniqueKeysWithValues: ProviderID.allCases.enumerated().map { ($1, $0) })
        let results = unordered.sorted { (order[$0.providerID] ?? .max) < (order[$1.providerID] ?? .max) }

        for snapshot in results where snapshot.status != .ok {
            Log.provider.notice("\(snapshot.providerID.rawValue) refresh returned \(snapshot.status.rawValue)")
        }

        let merged = SnapshotMerger.merge(fresh: results, cached: previous)
        let toSave = SnapshotMerger.snapshotsToSave(merged: merged, cached: previous)
        try? await store.save(toSave)
        Log.refresh.info("refresh complete: \(merged.count) vendors")
        return merged
    }

    private func snapshot(for provider: any ProviderClient) async -> ProviderSnapshot {
        let race = SnapshotRace()
        let timeout = timeoutSnapshot(for: provider)

        let providerTask = Task {
            await race.resolve(provider.snapshot())
        }
        let timeoutTask = Task { [providerTimeout] in
            let nanoseconds = UInt64(max(0, providerTimeout) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            race.resolve(timeout)
        }

        let result = await race.wait()
        providerTask.cancel()
        timeoutTask.cancel()
        return result
    }

    private func timeoutSnapshot(for provider: any ProviderClient) -> ProviderSnapshot {
        ProviderSnapshot(
            providerID: provider.providerID,
            status: .error,
            usedTokens: nil,
            primarySource: .api,
            confidence: .low,
            isEstimated: false,
            message: "Vendor refresh timed out after \(timeoutLabel)s"
        )
    }

    private var timeoutLabel: String {
        providerTimeout >= 1 ? String(Int(providerTimeout)) : String(format: "%.2f", providerTimeout)
    }
}

private final class SnapshotRace: @unchecked Sendable {
    private let lock = NSLock()
    private var result: ProviderSnapshot?
    private var continuation: CheckedContinuation<ProviderSnapshot, Never>?

    func resolve(_ snapshot: ProviderSnapshot) {
        lock.lock()
        guard result == nil else {
            lock.unlock()
            return
        }
        result = snapshot
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: snapshot)
    }

    func wait() async -> ProviderSnapshot {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let result {
                lock.unlock()
                continuation.resume(returning: result)
                return
            }
            self.continuation = continuation
            lock.unlock()
        }
    }
}
