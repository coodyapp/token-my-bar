import Foundation

/// Shared display-formatting helpers used across providers.
enum Format {
    /// Compact integer count, rounded to the nearest unit: `1_500` → "2K",
    /// `2_400_000` → "2M".
    static func count(_ value: Int) -> String {
        if value >= 1_000_000 { return "\(Int((Double(value) / 1_000_000).rounded()))M" }
        if value >= 1_000 {
            // Rounding can push the K value to 1000 (e.g. 999_999 → 999.999 →
            // 1000); roll it over to "1M" instead of emitting "1000K".
            let thousands = Int((Double(value) / 1_000).rounded())
            return thousands >= 1_000 ? "1M" : "\(thousands)K"
        }
        return "\(value)"
    }
}
