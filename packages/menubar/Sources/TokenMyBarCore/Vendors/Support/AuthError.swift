import Foundation

enum AuthError: Error {
    case missingCredentials
    case parseFailed
    /// Non-2xx HTTP response, carrying the status code so callers can
    /// distinguish auth failures (401/403) from transient/server errors.
    case http(Int)
}

struct OAuthCredentials {
    let accessToken: String
    let accountID: String?
}
