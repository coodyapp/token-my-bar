import Foundation

public struct ClaudeOAuthUsageProvider: ProviderClient {
    public let providerID: ProviderID = .claudeCode

    public init() {}

    public func snapshot() async -> ProviderSnapshot {
        do {
            let credentials = try Self.storedCredentials()
            var request = RemoteJSON.request(url: "https://api.anthropic.com/api/oauth/usage")
            request.setValue("Bearer \(credentials.token)", forHTTPHeaderField: "Authorization")
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            request.setValue("TokenMyBar/0.1 claude-code/unknown", forHTTPHeaderField: "User-Agent")
            return try await Self.snapshot(from: RemoteJSON.fetchObject(request), fallbackPlanName: credentials.planName)
        } catch {
            return .failure(
                error,
                providerID: providerID,
                source: .oauth,
                authSummary: "Claude OAuth",
                missingMessage: "Claude OAuth credentials not found",
                failureMessage: "Claude OAuth usage failed"
            )
        }
    }

    /// Extracts the plan badge ("Pro", "Max", "Team", …) from the stored
    /// credential payload; the usage API response itself carries no plan field.
    static func planFromKeychainPayload(_ object: Any) -> String? {
        guard let root = object as? [String: Any] else { return nil }
        let oauth = root["claudeAiOauth"] as? [String: Any] ?? root
        return RemoteJSON.planName(in: oauth, keys: [
            "subscriptionType", "subscription_type", "rateLimitTier", "rate_limit_tier",
        ])
    }

    static func snapshot(from object: [String: Any], fallbackPlanName: String? = nil) -> ProviderSnapshot {
        let session = RemoteJSON.findObject(in: object, keys: ["five_hour", "fiveHour"])
        let weekly = RemoteJSON.findObject(in: object, keys: ["seven_day", "sevenDay"])
        let sonnet = RemoteJSON.findObject(in: object, keys: ["seven_day_sonnet", "sevenDaySonnet"])
        let opus = RemoteJSON.findObject(in: object, keys: ["seven_day_opus", "sevenDayOpus"])
        let extra = RemoteJSON.findObject(in: object, keys: ["extra_usage", "extraUsage"])
        let percent = RemoteJSON.percent(in: session ?? weekly ?? object)
        var rows = [UsageRow]()
        if let session { rows.append(RemoteJSON.row(key: "session", title: "Session", iconName: "timer", object: session, idleDetail: "Starts when a message is sent")) }
        if let weekly { rows.append(RemoteJSON.row(key: "weekly", title: "Weekly", iconName: "calendar", object: weekly, idleDetail: "Starts when a message is sent")) }
        if let sonnet { rows.append(RemoteJSON.row(key: "sonnet", title: "Sonnet only", iconName: "arrow.triangle.2.circlepath", object: sonnet)) }
        if let opus { rows.append(RemoteJSON.row(key: "opus", title: "Opus", iconName: "sparkle", object: opus)) }
        if let extra, let extraRow = Self.extraUsageRow(extra) { rows.append(extraRow) }

        return ProviderSnapshot(
            providerID: .claudeCode,
            status: percent == nil && rows.isEmpty ? .noData : .ok,
            usedTokens: nil,
            unit: .tokens,
            usagePercent: percent,
            windowName: .session,
            resetAt: RemoteJSON.resetDate(in: session ?? weekly ?? object),
            refreshedAt: Date(),
            primarySource: .oauth,
            sources: [.oauth, .api],
            confidence: .high,
            isEstimated: false,
            message: rows.isEmpty ? "OAuth usage returned no windows" : nil,
            authSummary: "Claude OAuth",
            planName: RemoteJSON.planName(in: object, keys: ["subscriptionType", "subscription_type", "rate_limit_tier", "rateLimitTier", "plan"]) ?? fallbackPlanName,
            usageRows: rows
        )
    }

    /// Builds the "Usage credits" row from the OAuth `extra_usage` block.
    ///
    /// `monthly_limit` and `used_credits` are reported in cents. The block is
    /// ignored when `is_enabled` is false or the limit is missing/zero.
    static func extraUsageRow(_ extra: [String: Any]) -> UsageRow? {
        if let enabled = extra["is_enabled"] as? Bool, !enabled { return nil }

        let limitCents = doubleValue(extra, keys: ["monthly_limit", "monthlyLimit", "limit"])
        let usedCents = doubleValue(extra, keys: ["used_credits", "usedCredits", "spent", "used"])
        guard let limitCents, limitCents > 0 else { return nil }

        let used = (usedCents ?? 0) / 100
        let limit = limitCents / 100
        let percent = min(max(used / limit * 100, 0), 100)
        return UsageRow(
            key: "extra-usage",
            title: "Extra usage",
            subtitle: String(format: "This month: $%.2f / $%.2f", used, limit),
            value: "\(Int(percent.rounded()))%",
            detail: "\(Int(percent.rounded()))% used",
            iconName: "cart",
            percent: percent,
            unit: .cost
        )
    }

    private static func doubleValue(_ object: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = object[key] as? Double { return value }
            if let value = object[key] as? Int { return Double(value) }
            if let value = object[key] as? String, let parsed = Double(value) { return parsed }
        }
        return nil
    }

    struct StoredCredentials {
        let token: String
        let planName: String?
    }

    /// Resolves the Claude OAuth access token and plan from stored credentials.
    ///
    /// Order:
    /// 1. `~/.claude/.credentials.json` file (Linux / older CLI installs).
    /// 2. macOS Keychain item `Claude Code-credentials` written by Claude Code,
    ///    where the token lives under `claudeAiOauth.accessToken`.
    ///
    /// Reading the Keychain item is an explicit, OS-prompted user action.
    static func storedCredentials() throws -> StoredCredentials {
        let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/.credentials.json")
        if let data = try? Data(contentsOf: file),
           let object = try? JSONSerialization.jsonObject(with: data),
           let token = RemoteJSON.findString(in: object, keys: ["access_token", "accessToken"]) {
            return StoredCredentials(token: token, planName: planFromKeychainPayload(object))
        }

        // Scan every matching Keychain item and pick the first that actually
        // carries a Claude OAuth token, so an unrelated item under the same
        // service name can't shadow the real credential.
        for data in Keychain.genericPasswords(service: "Claude Code-credentials") {
            if let object = try? JSONSerialization.jsonObject(with: data),
               let token = tokenFromKeychainPayload(object) {
                return StoredCredentials(token: token, planName: planFromKeychainPayload(object))
            }
        }

        throw AuthError.missingCredentials
    }

    /// Extracts the access token from the Keychain JSON payload, preferring the
    /// `claudeAiOauth` block so unrelated `mcpOAuth` tokens are never used.
    static func tokenFromKeychainPayload(_ object: Any) -> String? {
        if let root = object as? [String: Any],
           let oauth = root["claudeAiOauth"] as? [String: Any],
           let token = RemoteJSON.findString(in: oauth, keys: ["access_token", "accessToken"]) {
            return token
        }
        return RemoteJSON.findString(in: object, keys: ["access_token", "accessToken"])
    }
}
