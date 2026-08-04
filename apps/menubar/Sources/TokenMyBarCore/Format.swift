import Foundation

/// Shared display-formatting helpers used across providers.
public enum Format {
    /// A spend figure in USD: "$21.40", "$0.00". Two decimals always, because a
    /// rounded-away cent reads as an estimate when the vendor gave an exact number.
    public static func money(_ amount: Double) -> String {
        guard amount.isFinite else { return "—" }
        return String(format: "$%.2f", amount)
    }

    /// How old a reading is, short enough to sit beside a vendor name:
    /// "just now", "12m old", "3h old", "25d old".
    public static func compactAge(since taken: Date, now: Date = Date()) -> String {
        let minutes = Int(now.timeIntervalSince(taken) / 60)
        if minutes < 2 { return "just now" }
        if minutes < 60 { return "\(minutes)m old" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h old" }
        return "\(hours / 24)d old"
    }

    /// "Resets in 2d 21h" / "Resets in 3h 4m" / "Resets in 12m".
    ///
    /// Callers format at display time from the stored reset date; formatting once
    /// at fetch time froze the countdown into cached rows.
    public static func resetCountdown(until reset: Date, now: Date = Date()) -> String {
        let minutes = max(0, Int(reset.timeIntervalSince(now) / 60))
        if minutes >= 24 * 60 { return "Resets in \(minutes / (24 * 60))d \((minutes % (24 * 60)) / 60)h" }
        if minutes >= 60 { return "Resets in \(minutes / 60)h \(minutes % 60)m" }
        return "Resets in \(minutes)m"
    }

    /// Rounded percent for display and accessibility: 69.6 → "70%". One home
    /// so a visible label and the value VoiceOver reads can never disagree.
    public static func percent(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        return "\(Int(value.rounded()))%"
    }

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
