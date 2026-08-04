import Foundation

/// Picks the one snapshot the CLI's `--json` payload reports.
///
/// Lives in Core so the decision is unit-testable; the CLI target has no test
/// bundle. Only an unknown vendor name is a usage error — a vendor missing
/// from the cache (disabled in the app, another process holding the refresh
/// lock on a cold cache) is a data condition, and the CLI still owes external
/// consumers a parseable payload for it.
public enum SnapshotSelection {
    public enum Outcome: Equatable {
        case snapshot(ProviderSnapshot)
        case unknownVendor(String)
        case unavailable(ProviderID?)
    }

    public static func select(
        from snapshots: [ProviderSnapshot],
        vendor: String?,
        primary: ProviderID?,
        combined: ProviderSnapshot?
    ) -> Outcome {
        if let vendor {
            guard let providerID = AppConfig.vendor(from: vendor) else {
                return .unknownVendor(vendor)
            }
            guard let snapshot = snapshots.first(where: { $0.providerID == providerID }) else {
                return .unavailable(providerID)
            }
            return .snapshot(snapshot)
        }

        if let primary, let snapshot = snapshots.first(where: { $0.providerID == primary }) {
            return .snapshot(snapshot)
        }

        if let snapshot = combined ?? snapshots.first {
            return .snapshot(snapshot)
        }

        return .unavailable(nil)
    }

    /// Stand-in report for `unavailable`, keeping the Waybar contract: valid
    /// JSON on stdout for every data condition, never an empty payload.
    public static func placeholderReport(for providerID: ProviderID?, now: Date = Date()) -> VendorUsageReport {
        let name = providerID?.displayName ?? "TokenMyBar"
        return VendorUsageReport(
            vendor: providerID?.rawValue ?? "none",
            name: name,
            plan: nil,
            status: ProviderStatus.noData.rawValue,
            text: "\(name) --",
            tooltip: providerID.map { "No snapshot available for \($0.rawValue). Run with --refresh first." }
                ?? "No snapshots available. Run with --refresh first.",
            percentage: nil,
            cssClass: "no-data",
            updatedAt: now,
            windows: []
        )
    }
}
