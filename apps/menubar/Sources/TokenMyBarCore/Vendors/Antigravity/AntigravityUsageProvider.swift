import Foundation

/// Google Antigravity quota, read from the same Code Assist endpoint the
/// Antigravity client itself calls.
///
/// Credentials come from `~/.gemini/oauth_creds.json`, written by the Antigravity
/// / Gemini sign-in. Nothing is written back.
///
/// The response reports `remainingFraction` — how much is LEFT, on a 0...1 scale
/// — which is the inverse of every other vendor here. It is converted once, at
/// the edge, so nothing downstream has to know: a bucket at `1` is 0% used, and
/// the vendor's own screen shows that same bucket as "100% remaining".
public struct AntigravityUsageProvider: ProviderClient {
    public let providerID: ProviderID = .antigravity
    private let credentialsURL: URL

    public init(credentialsURL: URL = AntigravityUsageProvider.defaultCredentialsURL()) {
        self.credentialsURL = credentialsURL
    }

    public static func defaultCredentialsURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["TOKEN_MY_BAR_GEMINI_CREDS"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/oauth_creds.json")
    }

    static let quotaURL = "https://daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota"

    public func snapshot() async -> ProviderSnapshot {
        do {
            let credentials = try await BlockingIO.run { try storedCredentials() }
            var request = RemoteJSON.request(url: Self.quotaURL)
            request.httpMethod = "POST"
            request.httpBody = Data("{}".utf8)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
            let quota = try await RemoteJSON.fetchObject(request)
            // The quota response carries no tier, so the plan badge costs a second
            // call. It is best-effort: a missing badge must never fail a refresh
            // that already has the numbers.
            let tier = try? await Self.fetchTier(accessToken: credentials.accessToken)
            return Self.snapshot(from: quota, expiresAt: credentials.expiresAt, tier: tier)
        } catch {
            return .failure(
                error,
                providerID: providerID,
                source: .oauth,
                authSummary: "Antigravity OAuth",
                missingMessage: "Antigravity credentials not found — sign in to Antigravity once",
                failureMessage: "Antigravity usage failed"
            )
        }
    }

    static let tierURL = "https://daily-cloudcode-pa.googleapis.com/v1internal:loadCodeAssist"

    /// The subscription tier, from the same call the Gemini clients make at
    /// startup. Only the default tier's name is used.
    static func fetchTier(accessToken: String) async throws -> String? {
        var request = RemoteJSON.request(url: tierURL)
        request.httpMethod = "POST"
        request.httpBody = Data(#"{"metadata":{"pluginType":"GEMINI"}}"#.utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return tierName(in: try await RemoteJSON.fetchObject(request))
    }

    static func tierName(in object: [String: Any]) -> String? {
        guard let tiers = object["allowedTiers"] as? [[String: Any]] else { return nil }
        let tier = tiers.first { $0["isDefault"] as? Bool == true } ?? tiers.first
        guard let id = tier?["id"] as? String else { return tier?["name"] as? String }
        // "standard-tier" -> "Standard"; the full names ("Gemini Code Assist") are
        // too long for a badge that sits beside the vendor name.
        return RemoteJSON.planName(in: ["tier": id.replacingOccurrences(of: "-tier", with: "")], keys: ["tier"])
    }

    static func snapshot(from object: [String: Any], expiresAt: Date? = nil, tier: String? = nil) -> ProviderSnapshot {
        let buckets = (object["buckets"] as? [[String: Any]]) ?? []
        let rows = Self.rows(from: buckets)
        let worst = rows.compactMap(\.percent).max()

        return ProviderSnapshot(
            providerID: .antigravity,
            status: buckets.isEmpty ? .noData : .ok,
            usedTokens: nil,
            unit: .requests,
            usagePercent: worst,
            windowName: .unknown,
            resetAt: rows.compactMap(\.resetAt).min(),
            refreshedAt: Date(),
            primarySource: .oauth,
            sources: [.oauth, .api],
            confidence: .high,
            isEstimated: false,
            message: buckets.isEmpty ? "Antigravity reported no quota buckets" : Self.expiryNotice(expiresAt),
            authSummary: "Antigravity OAuth",
            planName: tier ?? Self.planName(in: object),
            usageRows: rows
        )
    }

    /// One row per model bucket, worst first, so the model closest to its cap is
    /// the one the popover leads with.
    static func rows(from buckets: [[String: Any]]) -> [UsageRow] {
        buckets.compactMap { bucket -> UsageRow? in
            guard let modelID = bucket["modelId"] as? String ?? bucket["model_id"] as? String else { return nil }
            // Gemini models only. Antigravity meters its Claude and GPT models in
            // a separate group with its own limits, and mixing the two groups into
            // one list reads as one pool that they are not.
            guard modelID.lowercased().hasPrefix("gemini") else { return nil }
            let used = Self.usedPercent(in: bucket)
            return UsageRow(
                key: "model-\(modelID)",
                title: Self.modelTitle(modelID),
                subtitle: (bucket["tokenType"] as? String).map { $0.lowercased() },
                value: used.map { "\(Int($0.rounded()))%" } ?? "—",
                iconName: "cpu",
                resetAt: RemoteJSON.resetDate(in: bucket),
                percent: used,
                unit: .requests
            )
        }
        .sorted { ($0.percent ?? -1, $0.key) > ($1.percent ?? -1, $1.key) }
    }

    /// `remainingFraction` is 0...1 of quota LEFT; every other provider and the
    /// whole UI speak percent used.
    static func usedPercent(in bucket: [String: Any]) -> Double? {
        guard let remaining = RemoteJSON.double(bucket, keys: ["remainingFraction", "remaining_fraction"]),
              remaining.isFinite
        else { return nil }
        return min(max((1 - remaining) * 100, 0), 100)
    }

    /// "gemini-2.5-flash-lite" -> "Gemini 2.5 Flash Lite".
    static func modelTitle(_ modelID: String) -> String {
        modelID
            .split(separator: "-")
            .map { part in
                part.allSatisfy(\.isNumber) || part.contains(".")
                    ? String(part)
                    : part.prefix(1).uppercased() + part.dropFirst()
            }
            .joined(separator: " ")
    }

    static func planName(in object: [String: Any]) -> String? {
        RemoteJSON.planName(in: object, keys: ["tier", "tierId", "tier_id", "plan", "currentTier"])
    }

    /// The access token is short-lived and the app never refreshes it — saying so
    /// before it lapses is the difference between one command and a dead vendor.
    static func expiryNotice(_ expiresAt: Date?, now: Date = Date()) -> String? {
        guard let expiresAt else { return nil }
        guard expiresAt > now else { return "Antigravity sign-in expired — open Antigravity once to renew" }
        return nil
    }

    struct StoredCredentials: Sendable {
        let accessToken: String
        let expiresAt: Date?
    }

    /// Reading the credential file blocks only on local IO, but it is grouped with
    /// the other credential reads for consistency.
    func storedCredentials() throws -> StoredCredentials {
        guard let data = try? Data(contentsOf: credentialsURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = RemoteJSON.findString(in: object, keys: ["access_token", "accessToken"])
        else { throw AuthError.missingCredentials }
        let expiry = RemoteJSON.double(object, keys: ["expiry_date", "expiryDate", "expires_at"])
        return StoredCredentials(
            accessToken: token,
            // `expiry_date` is milliseconds since the epoch.
            expiresAt: expiry.map { Date(timeIntervalSince1970: $0 > 10_000_000_000 ? $0 / 1000 : $0) }
        )
    }
}
