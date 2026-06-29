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
        } catch AuthError.missingCredentials {
            return missingAuth("Codex OAuth credentials not found")
        } catch {
            return errorSnapshot("Codex OAuth usage failed")
        }
    }

    static func snapshot(from object: [String: Any]) -> ProviderSnapshot {
        let rateLimit = RemoteJSON.findObject(in: object, keys: ["rate_limit", "rateLimit"])
        let primary = RemoteJSON.findObject(in: rateLimit ?? object, keys: ["primary_window", "primaryWindow", "five_hour", "fiveHour"])
        let weekly = RemoteJSON.findObject(in: rateLimit ?? object, keys: ["secondary_window", "secondaryWindow", "weekly", "seven_day", "sevenDay"])
        let percent = RemoteJSON.percent(in: primary ?? object)
        var rows = [UsageRow]()
        if let primary { rows.append(RemoteJSON.row(key: "session", title: "Session", iconName: "timer", object: primary)) }
        if let weekly { rows.append(RemoteJSON.row(key: "weekly", title: "Weekly", iconName: "calendar", object: weekly)) }

        return ProviderSnapshot(
            providerID: .codex,
            status: percent == nil && rows.isEmpty ? .noData : .ok,
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
            message: rows.isEmpty ? "OAuth usage returned no windows" : nil,
            authSummary: "Codex OAuth",
            planName: RemoteJSON.planName(in: object, keys: ["plan_type", "planType", "plan"]),
            usageRows: rows
        )
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

    private func missingAuth(_ message: String) -> ProviderSnapshot {
        ProviderSnapshot(providerID: providerID, status: .unauthenticated, usedTokens: nil, primarySource: .oauth, sources: [.oauth], confidence: .low, isEstimated: false, message: message, authSummary: "Codex OAuth")
    }

    private func errorSnapshot(_ message: String) -> ProviderSnapshot {
        ProviderSnapshot(providerID: providerID, status: .error, usedTokens: nil, primarySource: .oauth, sources: [.oauth, .api], confidence: .low, isEstimated: false, message: message, authSummary: "Codex OAuth")
    }
}
