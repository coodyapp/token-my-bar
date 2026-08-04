import Foundation

/// Saturating sum: per-value clamping alone still leaves running totals able
/// to overflow across a very large corrupt source, and an overflow here traps.
func clampedSum(_ values: Int...) -> Int {
    values.reduce(0) { partial, value in
        let (sum, overflow) = partial.addingReportingOverflow(value)
        return overflow ? .max : sum
    }
}
