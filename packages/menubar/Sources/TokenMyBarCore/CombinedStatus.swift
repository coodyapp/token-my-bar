import Foundation

public struct CombinedStatus: Equatable, Sendable {
    public let title: String
    public let snapshot: ProviderSnapshot?

    public init(title: String, snapshot: ProviderSnapshot?) {
        self.title = title
        self.snapshot = snapshot
    }
}

public enum CombinedStatusFormatter {
    /// Filters to vendors with a usable (ok/stale) snapshot and, when a primary
    /// vendor is configured and present, moves it to the front. Shared by the
    /// CLI's combined status and the menu bar title so both follow one
    /// resolution order instead of two hand-kept copies.
    public static func orderedUsableSnapshots(_ snapshots: [ProviderSnapshot], primary: ProviderID?) -> [ProviderSnapshot] {
        let usable = snapshots.filter { $0.status == .ok || $0.status == .stale }
        guard let primary, let primarySnapshot = usable.first(where: { $0.providerID == primary }) else {
            return usable
        }
        return [primarySnapshot] + usable.filter { $0.providerID != primary }
    }

    /// Builds the menu bar title from active vendors with official percentages.
    /// Falls back to `--` when no vendor exposes an official percentage.
    public static func format(_ snapshots: [ProviderSnapshot], primary: ProviderID? = nil) -> CombinedStatus {
        let ordered = orderedUsableSnapshots(snapshots, primary: primary)
        let displayed = ordered.compactMap { snapshot -> (ProviderSnapshot, String)? in
            guard let percent = snapshot.usagePercent else { return nil }
            return (snapshot, title(for: percent))
        }

        return CombinedStatus(
            title: displayed.isEmpty ? "--" : displayed.map(\.1).joined(separator: " | "),
            snapshot: displayed.first?.0
        )
    }

    private static func title(for percent: Double) -> String {
        "\(Int(percent.rounded()))%"
    }
}
