import Foundation

/// Shared builders for the non-`.ok` snapshots every official provider returns,
/// so a new vendor doesn't re-copy the `unauthenticated`/`error`/`no-data`
/// boilerplate and HTTP-status mapping lives in exactly one place.
extension ProviderSnapshot {
    /// Maps a thrown provider error to the right user-facing snapshot.
    ///
    /// - `missingCredentials` → unauthenticated with `missingMessage`.
    /// - HTTP 401/403 → unauthenticated ("sign in"): the token exists but was
    ///   rejected, which is actionable differently from a server error.
    /// - any other HTTP status → error, with the code preserved for diagnostics.
    /// - everything else → generic error with `failureMessage`.
    static func failure(
        _ error: Error,
        providerID: ProviderID,
        source: UsageSource,
        authSummary: String,
        missingMessage: String,
        failureMessage: String
    ) -> ProviderSnapshot {
        switch error {
        case AuthError.missingCredentials:
            return unauthenticated(providerID, source: source, message: missingMessage, authSummary: authSummary)
        case AuthError.http(401), AuthError.http(403):
            return unauthenticated(providerID, source: source, message: "Authentication expired — sign in again", authSummary: authSummary)
        case AuthError.http(let status):
            return errored(providerID, source: source, message: "\(failureMessage) (HTTP \(status))", authSummary: authSummary)
        default:
            return errored(providerID, source: source, message: failureMessage, authSummary: authSummary)
        }
    }

    static func unauthenticated(
        _ providerID: ProviderID,
        source: UsageSource,
        message: String,
        authSummary: String
    ) -> ProviderSnapshot {
        ProviderSnapshot(
            providerID: providerID,
            status: .unauthenticated,
            usedTokens: nil,
            primarySource: source,
            sources: [source],
            confidence: .low,
            isEstimated: false,
            message: message,
            authSummary: authSummary
        )
    }

    static func errored(
        _ providerID: ProviderID,
        source: UsageSource,
        message: String,
        authSummary: String
    ) -> ProviderSnapshot {
        ProviderSnapshot(
            providerID: providerID,
            status: .error,
            usedTokens: nil,
            primarySource: source,
            sources: [source, .api],
            confidence: .low,
            isEstimated: false,
            message: message,
            authSummary: authSummary
        )
    }

    static func noData(
        _ providerID: ProviderID,
        source: UsageSource,
        message: String,
        authSummary: String
    ) -> ProviderSnapshot {
        ProviderSnapshot(
            providerID: providerID,
            status: .noData,
            usedTokens: nil,
            primarySource: source,
            sources: [source, .api],
            confidence: .low,
            isEstimated: false,
            message: message,
            authSummary: authSummary
        )
    }
}
