import Foundation

/// Shared display-formatting helpers used across providers.
enum Format {
    /// Compact integer count: `1_500` → "1K", `2_000_000` → "2M".
    static func count(_ value: Int) -> String {
        if value >= 1_000_000 { return "\(value / 1_000_000)M" }
        if value >= 1_000 { return "\(value / 1_000)K" }
        return "\(value)"
    }
}
