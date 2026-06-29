import Foundation

enum AuthError: Error {
    case missingCredentials
    case parseFailed
}

struct OAuthCredentials {
    let accessToken: String
    let accountID: String?
}
