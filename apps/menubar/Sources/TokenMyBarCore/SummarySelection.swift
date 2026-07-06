import Foundation

/// Chooses which vendor a "Selected Provider" summary should display.
public enum SummarySelection {
    /// Returns the segment for `primary`, falling back to the first segment
    /// when no primary is configured or the configured one isn't present.
    ///
    /// Returns `nil` only when there are no segments — so a `--` placeholder is
    /// shown solely when there is genuinely no usable data, never merely because
    /// `primaryVendor` was left unset (its default).
    public static func selected<Segment>(
        _ segments: [Segment],
        primary: ProviderID?,
        id: (Segment) -> ProviderID
    ) -> Segment? {
        if let primary, let match = segments.first(where: { id($0) == primary }) {
            return match
        }
        return segments.first
    }
}
