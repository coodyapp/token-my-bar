import Foundation

/// Shared display-formatting helpers used across providers.
enum Format {
    /// Compact integer count, rounded to the nearest unit: `1_500` → "2K",
    /// `2_400_000` → "2M".
    static func count(_ value: Int) -> String {
        if value >= 1_000_000 { return "\(Int((Double(value) / 1_000_000).rounded()))M" }
        if value >= 1_000 { return "\(Int((Double(value) / 1_000).rounded()))K" }
        return "\(value)"
    }
}
