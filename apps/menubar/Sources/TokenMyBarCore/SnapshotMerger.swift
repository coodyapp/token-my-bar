import Foundation

/// Pure merge rules shared by every refresh path (app + CLI).
///
/// Keeps last-good cached data visible when a fresh fetch fails, and decides
/// what gets persisted so a transient failure never overwrites good data.
public enum SnapshotMerger {
    /// What to show now and what to keep on disk.
    ///
    /// Both come out of one decision per vendor on purpose: when display and
    /// persistence derived their own rules, they drifted apart and the cache
    /// froze at pre-failure numbers while the app showed current ones. What gets
    /// persisted is now exactly what gets shown — the two lists differ only in
    /// that `persist` also carries vendors this refresh never touched.
    public struct Resolution: Equatable, Sendable {
        public let display: [ProviderSnapshot]
        public let persist: [ProviderSnapshot]
    }

    public static func resolve(fresh: [ProviderSnapshot], cached: [ProviderSnapshot]) -> Resolution {
        let cachedByID = index(cached)

        let resolved = fresh.map { snapshot -> ProviderSnapshot in
            let fallback = cachedByID[snapshot.providerID].flatMap { hasUsableData($0) ? $0 : nil }
            // A failed fetch can still carry current data — the local-log fallback
            // keeps reporting after an OAuth token expires — and older cached
            // numbers must neither displace it on screen nor outlive it on disk.
            guard shouldUseCached(for: snapshot), !hasUsableData(snapshot), let fallback else {
                return snapshot
            }
            // The cache is all that is left, so re-present it — keeping its own
            // numbers and the time they were taken, but reporting the state that
            // actually applies now. Expired auth keeps saying "sign in" rather
            // than being laundered into "stale", which reads as a
            // retry-and-it-fixes-itself state.
            // A vendor already known to need re-authentication still needs it
            // after an unrelated failure — a dropped network downgrading "sign in"
            // to "stale" would tell the user to wait for something that will never
            // fix itself.
            guard snapshot.status == .unauthenticated || fallback.status == .unauthenticated else {
                return fallback.staleCopy(message: "Using cached data; latest refresh returned \(snapshot.status.rawValue)")
            }
            let signIn = snapshot.status == .unauthenticated ? snapshot.message : fallback.message
            return fallback.staleCopy(
                status: .unauthenticated,
                message: signIn ?? "Sign in again; showing cached data"
            )
        }

        // A subset refresh (only some providers enabled) must not drop the other
        // vendors' last-good data from the shared cache; preserve any cached
        // provider that wasn't part of this refresh.
        let refreshedIDs = Set(fresh.map(\.providerID))
        let untouched = cached.filter { !refreshedIDs.contains($0.providerID) }

        return Resolution(
            display: inCanonicalOrder(resolved),
            persist: inCanonicalOrder(resolved + untouched)
        )
    }

    public static func shouldUseCached(for snapshot: ProviderSnapshot) -> Bool {
        switch snapshot.status {
        case .error, .noData, .unauthenticated: true
        case .ok, .loading, .stale: false
        }
    }

    /// True when a snapshot carries numbers worth showing or keeping.
    private static func hasUsableData(_ snapshot: ProviderSnapshot) -> Bool {
        snapshot.usedTokens != nil || snapshot.usagePercent != nil || !snapshot.usageRows.isEmpty
    }

    /// Task-group completion order is a network race. One fixed vendor order
    /// keeps the popover, the menu bar, and every cache reader in agreement.
    private static func inCanonicalOrder(_ snapshots: [ProviderSnapshot]) -> [ProviderSnapshot] {
        let order = Dictionary(uniqueKeysWithValues: ProviderID.allCases.enumerated().map { ($1, $0) })
        return snapshots.sorted { (order[$0.providerID] ?? .max) < (order[$1.providerID] ?? .max) }
    }

    private static func index(_ snapshots: [ProviderSnapshot]) -> [ProviderID: ProviderSnapshot] {
        Dictionary(snapshots.map { ($0.providerID, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
