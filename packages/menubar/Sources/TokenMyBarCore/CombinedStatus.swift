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
    /// Builds the menu bar title from active vendors with official percentages.
    /// Falls back to `--` when no vendor exposes an official percentage.
    public static func format(_ snapshots: [ProviderSnapshot], primary: ProviderID? = nil) -> CombinedStatus {
        let usable = snapshots.filter { $0.status == .ok || $0.status == .stale }

        let ordered: [ProviderSnapshot]
        if let primary, let primarySnapshot = usable.first(where: { $0.providerID == primary }) {
            ordered = [primarySnapshot] + usable.filter { $0.providerID != primary }
        } else {
            ordered = usable
        }
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
