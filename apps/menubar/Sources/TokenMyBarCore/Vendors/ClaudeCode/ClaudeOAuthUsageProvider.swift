import Foundation

public struct ClaudeOAuthUsageProvider: ProviderClient {
    public let providerID: ProviderID = .claudeCode

    public init() {}

    public func snapshot() async -> ProviderSnapshot {
        do {
            let credentials = try await BlockingIO.run { try Self.storedCredentials() }
            var request = RemoteJSON.request(url: "https://api.anthropic.com/api/oauth/usage")
            request.setValue("Bearer \(credentials.token)", forHTTPHeaderField: "Authorization")
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            request.setValue("TokenMyBar/1.0 claude-code/unknown", forHTTPHeaderField: "User-Agent")
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

    /// Rows from the `limits` array, in the order Claude sends them.
    ///
    /// Each entry names its own window (`kind`) and, for a per-model cap, the
    /// model under `scope.model.display_name` — so a cap the account gains later
    /// is labelled correctly without a code change.
    static func rows(fromLimits object: [String: Any]) -> [UsageRow] {
        guard let limits = object["limits"] as? [[String: Any]] else { return [] }
        return limits.map { limit in
            let kind = limit["kind"] as? String ?? "limit"
            let model = (limit["scope"] as? [String: Any])
                .flatMap { $0["model"] as? [String: Any] }
                .flatMap { $0["display_name"] as? String }
            // `percent` is rejected by the shared reader because the field name
            // alone does not say used-or-remaining. Here it does: this structure
            // is percent used, verified against the account's own usage screen.
            let percent = RemoteJSON.double(limit, keys: ["percent", "utilization"])
                .flatMap(RemoteJSON.normalizePercent)
            let reset = RemoteJSON.resetDate(in: limit)
            return UsageRow(
                key: Self.rowKey(forLimitKind: kind, model: model),
                title: Self.title(forLimitKind: kind, model: model),
                value: percent.map { "\(Int($0.rounded()))%" } ?? "—",
                detail: reset == nil ? "Starts when a message is sent" : nil,
                iconName: model != nil ? "cpu" : (kind == "session" ? "timer" : "calendar"),
                resetAt: reset,
                percent: percent,
                unit: .tokens
            )
        }
    }

    /// Keeps the stable keys the rest of the app switches on (`session`,
    /// `weekly`) so window labelling and icons keep working.
    private static func rowKey(forLimitKind kind: String, model: String?) -> String {
        if let model { return "weekly-\(model.lowercased())" }
        return kind == "session" ? "session" : "weekly"
    }

    private static func title(forLimitKind kind: String, model: String?) -> String {
        if let model { return "\(model) only" }
        return kind == "session" ? "Session" : "Weekly"
    }

    /// "seven_day_sonnet" -> "Sonnet only" for accounts still on the older shape.
    static func modelWindowTitle(for key: String) -> String {
        let model = key
            .replacingOccurrences(of: "seven_day_", with: "")
            .replacingOccurrences(of: "sevenDay", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespaces)
        guard !model.isEmpty else { return "Weekly" }
        return "\(model.prefix(1).uppercased() + model.dropFirst()) only"
    }

    /// Extracts the plan badge ("Pro", "Max", "Team", …) from the stored
    /// credential payload; the usage API response itself carries no plan field.
    /// The rate-limit tier wins over the subscription type: both are present and
    /// they disagree — a Max 5x account reports `subscriptionType: "max"` with
    /// `rateLimitTier: "default_claude_max_5x"` — and the tier is what the
    /// percentages on screen are a share of.
    static func planFromKeychainPayload(_ object: Any) -> String? {
        guard let root = object as? [String: Any] else { return nil }
        let oauth = root["claudeAiOauth"] as? [String: Any] ?? root
        let tier = RemoteJSON.findString(in: oauth, keys: ["rateLimitTier", "rate_limit_tier"])
            .map { $0.replacingOccurrences(of: "default_claude_", with: "") }
        guard let tier, !tier.isEmpty else {
            return RemoteJSON.planName(in: oauth, keys: ["subscriptionType", "subscription_type"])
        }
        return RemoteJSON.planName(in: ["tier": tier], keys: ["tier"])
    }

    static func snapshot(from object: [String: Any], fallbackPlanName: String? = nil) -> ProviderSnapshot {
        let session = RemoteJSON.findObject(in: object, keys: ["five_hour", "fiveHour"])
        let weekly = RemoteJSON.findObject(in: object, keys: ["seven_day", "sevenDay"])
        let extra = RemoteJSON.findObject(in: object, keys: ["extra_usage", "extraUsage"])
        let percent = RemoteJSON.percent(in: session ?? weekly ?? object)
        // `limits` is the shape Claude Code's own usage screen reads: one entry per
        // window, each naming its scope. It carries per-model caps the top-level
        // `seven_day_*` keys report as null, so a plan's "Fable" limit only exists
        // here. The older keys stay as the fallback for accounts without it.
        var rows = Self.rows(fromLimits: object)
        if rows.isEmpty {
            if let session { rows.append(RemoteJSON.row(key: "session", title: "Session", iconName: "timer", object: session, idleDetail: "Starts when a message is sent")) }
            if let weekly { rows.append(RemoteJSON.row(key: "weekly", title: "Weekly", iconName: "calendar", object: weekly, idleDetail: "Starts when a message is sent")) }
            // Accounts still on the older shape carry per-model caps as
            // `seven_day_<model>` keys; enumerate rather than name them.
            for window in RemoteJSON.windows(in: object, prefixes: ["seven_day_", "sevenDay"], excluding: ["seven_day", "sevenDay"]) {
                rows.append(RemoteJSON.row(
                    key: window.key,
                    title: Self.modelWindowTitle(for: window.key),
                    iconName: "cpu",
                    object: window.object
                ))
            }
        }
        if let extra, let extraRow = Self.extraUsageRow(extra) { rows.append(extraRow) }
        let unreadable = RemoteJSON.unreadableWindow(in: rows)

        return ProviderSnapshot(
            providerID: .claudeCode,
            status: unreadable != nil ? .error : (percent == nil && rows.isEmpty ? .noData : .ok),
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
            message: unreadable.map { "Usage payload changed: no percentage in the \($0.title) window" }
                ?? (rows.isEmpty ? "OAuth usage returned no windows" : nil),
            authSummary: "Claude OAuth",
            // The rate-limit tier wins over the subscription type: the tier is what
            // the percentages on screen are a share of, and the two disagree (a
            // Max 5x account reports subscriptionType "pro").
            planName: RemoteJSON.planName(in: object, keys: ["rate_limit_tier", "rateLimitTier", "subscriptionType", "subscription_type", "plan"]) ?? fallbackPlanName,
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

    struct StoredCredentials: Sendable {
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
    /// Reading the Keychain item is an explicit, OS-prompted user action, so this
    /// blocks until the user answers: call it through `BlockingIO`.
    static func storedCredentials() throws -> StoredCredentials {
        let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/.credentials.json")
        if let data = try? Data(contentsOf: file),
           let object = try? JSONSerialization.jsonObject(with: data),
           let token = tokenFromKeychainPayload(object) {
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
