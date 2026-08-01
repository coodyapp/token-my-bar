import Foundation

public struct CodexOAuthUsageProvider: ProviderClient {
    public let providerID: ProviderID = .codex

    public init() {}

    public func snapshot() async -> ProviderSnapshot {
        do {
            let credentials = try Self.credentials()
            var request = RemoteJSON.request(url: "https://chatgpt.com/backend-api/wham/usage")
            request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
            if let accountID = credentials.accountID {
                request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
            }
            return try await Self.snapshot(from: RemoteJSON.fetchObject(request))
        } catch {
            return .failure(
                error,
                providerID: providerID,
                source: .oauth,
                authSummary: "Codex OAuth",
                missingMessage: "Codex OAuth credentials not found",
                failureMessage: "Codex OAuth usage failed"
            )
        }
    }

    static func snapshot(from object: [String: Any]) -> ProviderSnapshot {
        let rateLimit = RemoteJSON.findObject(in: object, keys: ["rate_limit", "rateLimit"])
        let primary = RemoteJSON.findObject(in: rateLimit ?? object, keys: ["primary_window", "primaryWindow", "five_hour", "fiveHour"])
        let weekly = RemoteJSON.findObject(in: rateLimit ?? object, keys: ["secondary_window", "secondaryWindow", "weekly", "seven_day", "sevenDay"])
        // wham/usage reports used_percent, already percent *used* (verified
        // against the live payload — the dashboard's "99% remaining" is its
        // own inversion of used_percent: 1).
        let percent = RemoteJSON.percent(in: primary ?? object)
        var rows = [UsageRow]()
        // The window a plan calls "primary" is not always the 5-hour one — a Plus
        // account's primary_window is `limit_window_seconds: 604800`, i.e. the
        // weekly limit its own /status screen reports. Label from the declared
        // length rather than from the field name.
        if let primary { rows.append(Self.windowRow(primary, fallbackKey: "session")) }
        if let weekly { rows.append(Self.windowRow(weekly, fallbackKey: "weekly")) }
        let unreadable = RemoteJSON.unreadableWindow(in: rows)

        return ProviderSnapshot(
            providerID: .codex,
            status: unreadable != nil ? .error : (percent == nil && rows.isEmpty ? .noData : .ok),
            usedTokens: nil,
            unit: .tokens,
            usagePercent: percent,
            windowName: .session,
            resetAt: RemoteJSON.resetDate(in: primary ?? object),
            refreshedAt: Date(),
            primarySource: .oauth,
            sources: [.oauth, .api],
            confidence: .high,
            isEstimated: false,
            message: unreadable.map { "Usage payload changed: no percentage in the \($0.title) window" }
                ?? (rows.isEmpty ? "OAuth usage returned no windows" : nil),
            authSummary: "Codex OAuth",
            planName: RemoteJSON.planName(in: object, keys: ["plan_type", "planType", "plan"]),
            usageRows: rows
        )
    }

    /// Names a window by how long it actually lasts, falling back to the field it
    /// arrived in when the vendor omits the length.
    static func windowRow(_ window: [String: Any], fallbackKey: String) -> UsageRow {
        let key: String
        let title: String
        let icon: String
        if let seconds = RemoteJSON.double(window, keys: ["limit_window_seconds", "limitWindowSeconds"]) {
            if seconds >= 20 * 24 * 3600 {
                (key, title, icon) = ("monthly", "Monthly", "calendar.badge.clock")
            } else if seconds >= 24 * 3600 {
                (key, title, icon) = ("weekly", "Weekly", "calendar")
            } else {
                (key, title, icon) = ("session", "Session", "timer")
            }
        } else {
            let isSession = fallbackKey == "session"
            (key, title, icon) = (fallbackKey, isSession ? "Session" : "Weekly", isSession ? "timer" : "calendar")
        }
        return RemoteJSON.row(key: key, title: title, iconName: icon, object: window)
    }

    private static func credentials() throws -> OAuthCredentials {
        let home = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
        let file = home.appendingPathComponent("auth.json")
        guard let data = try? Data(contentsOf: file),
              let object = try? JSONSerialization.jsonObject(with: data),
              let token = RemoteJSON.findString(in: object, keys: ["access_token", "accessToken"])
        else { throw AuthError.missingCredentials }
        return OAuthCredentials(
            accessToken: token,
            accountID: RemoteJSON.findString(in: object, keys: ["account_id", "accountId"])
        )
    }
}
