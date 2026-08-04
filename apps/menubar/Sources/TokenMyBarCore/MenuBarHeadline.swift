import Foundation

/// The one number per vendor that belongs in the menu bar.
///
/// A vendor publishes several windows and any single one of them at 100% stops
/// the user working, so the headline is the *worst* window rather than the
/// session — the session is near zero precisely between sessions, which is when
/// people glance at the bar. The window is named alongside it, because "76%"
/// means nothing if the reader cannot tell whether it is five hours or a week.
public struct MenuBarHeadline: Equatable, Sendable {
    public let providerID: ProviderID
    public let percent: Double
    /// Short label for the window the percent came from, e.g. "5h", "wk".
    public let windowLabel: String
    /// True when the reading is not current: cached, expired auth, or a window
    /// that has certainly rolled over since it was fetched.
    public let isStale: Bool

    public init(providerID: ProviderID, percent: Double, windowLabel: String, isStale: Bool) {
        self.providerID = providerID
        self.percent = percent
        self.windowLabel = windowLabel
        self.isStale = isStale
    }

    public var percentText: String {
        "\(Int(percent.rounded()))%"
    }

    /// Builds the headline for one snapshot, or `nil` when the vendor has no
    /// number worth showing.
    ///
    /// A row whose window has already elapsed is dropped: its percentage
    /// describes a period that is over, so presenting it as the current load is
    /// how a fully-spent week reads as a quiet morning.
    public static func from(_ snapshot: ProviderSnapshot, now: Date = Date()) -> MenuBarHeadline? {
        let stale = isStale(snapshot)
        let live = snapshot.usageRows.filter { row in
            guard row.percent != nil else { return false }
            guard let resetAt = row.resetAt else { return true }
            return resetAt > now
        }
        guard let worst = live.max(by: { ($0.percent ?? 0) < ($1.percent ?? 0) }) else {
            // No usable window: fall back to the snapshot's own percent, which
            // vendors set from their primary window.
            guard let percent = snapshot.usagePercent, !snapshot.usageRows.contains(where: { $0.resetAt != nil }) else { return nil }
            return MenuBarHeadline(providerID: snapshot.providerID, percent: percent, windowLabel: "", isStale: stale)
        }
        return MenuBarHeadline(
            providerID: snapshot.providerID,
            percent: worst.percent ?? 0,
            windowLabel: windowLabel(forRowKey: worst.key),
            isStale: stale
        )
    }

    public static func all(_ snapshots: [ProviderSnapshot], now: Date = Date()) -> [MenuBarHeadline] {
        snapshots.compactMap { from($0, now: now) }
    }

    /// True when a vendor that belongs in the bar produced no headline.
    /// Expired auth and errors always qualify; so does a vendor that had a
    /// number (a percent on the snapshot or any row) but shows nothing — the
    /// elapsed-window drop above is deliberate, and this is its counterpart
    /// so the vendor is flagged rather than silently vanishing.
    public static func needsAttention(_ snapshots: [ProviderSnapshot], shown: Set<ProviderID>) -> Bool {
        snapshots.contains { snapshot in
            guard !shown.contains(snapshot.providerID) else { return false }
            switch snapshot.status {
            case .unauthenticated, .error:
                return true
            case .ok, .stale:
                return snapshot.usagePercent != nil || snapshot.usageRows.contains { $0.percent != nil }
            case .noData, .loading:
                return false
            }
        }
    }

    private static func isStale(_ snapshot: ProviderSnapshot) -> Bool {
        switch snapshot.status {
        case .ok: false
        case .stale, .unauthenticated, .error, .noData, .loading: true
        }
    }

    /// Row keys are provider-defined; these are the windows they all use.
    static func windowLabel(forRowKey key: String) -> String {
        switch key {
        case "session", "rolling": "5h"
        case "weekly": "wk"
        case "monthly", "billing": "mo"
        default: key.hasPrefix("seven_day") || key.hasPrefix("sevenDay") ? "wk" : ""
        }
    }
}
