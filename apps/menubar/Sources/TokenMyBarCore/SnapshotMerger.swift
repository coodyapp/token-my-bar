import Foundation

/// Pure merge rules shared by every refresh path (app + CLI).
///
/// Keeps last-good cached data visible when a fresh fetch fails, and decides
/// what gets persisted so a transient failure never overwrites good data.
public enum SnapshotMerger {
    public static func merge(fresh: [ProviderSnapshot], cached: [ProviderSnapshot]) -> [ProviderSnapshot] {
        let cachedByID = index(cached)
        return fresh.map { snapshot in
            guard shouldUseCached(for: snapshot),
                  let cachedSnapshot = cachedByID[snapshot.providerID],
                  cachedSnapshot.usedTokens != nil || cachedSnapshot.usagePercent != nil || !cachedSnapshot.usageRows.isEmpty
            else { return snapshot }
            return cachedSnapshot.staleCopy(message: "Using cached data; latest refresh returned \(snapshot.status.rawValue)")
        }
    }

    public static func snapshotsToSave(merged: [ProviderSnapshot], cached: [ProviderSnapshot]) -> [ProviderSnapshot] {
        let cachedByID = index(cached)
        let refreshed = merged.map { snapshot in
            snapshot.status == .stale ? (cachedByID[snapshot.providerID] ?? snapshot) : snapshot
        }
        // A subset refresh (only some providers enabled) must not drop the
        // other vendors' last-good data from the shared cache; preserve any
        // cached provider that wasn't part of this refresh.
        let mergedIDs = Set(merged.map(\.providerID))
        let untouched = cached.filter { !mergedIDs.contains($0.providerID) }
        // Keep the persisted order canonical so cache reads (CLI/other
        // instances) get one fixed vendor order rather than fresh-then-cached.
        let order = Dictionary(uniqueKeysWithValues: ProviderID.allCases.enumerated().map { ($1, $0) })
        return (refreshed + untouched).sorted { (order[$0.providerID] ?? .max) < (order[$1.providerID] ?? .max) }
    }

    public static func shouldUseCached(for snapshot: ProviderSnapshot) -> Bool {
        switch snapshot.status {
        case .error, .noData, .unauthenticated: true
        case .ok, .loading, .stale: false
        }
    }

    private static func index(_ snapshots: [ProviderSnapshot]) -> [ProviderID: ProviderSnapshot] {
        Dictionary(snapshots.map { ($0.providerID, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
