import Foundation

public struct OpenCodeCookieUsageProvider: ProviderClient {
    public let providerID: ProviderID = .opencode

    public init() {}

    public func snapshot() async -> ProviderSnapshot {
        do {
            let cookie = try Self.cookieHeader()
            let workspaceIDs = try await Self.workspaceIDs(cookie: cookie)
            for workspaceID in workspaceIDs {
                guard let object = try? await Self.usageObject(cookie: cookie, workspaceID: workspaceID) else { continue }
                let snapshot = Self.snapshot(from: object)
                if snapshot.status == .ok { return snapshot }
            }
            return ProviderSnapshot(providerID: providerID, status: .noData, usedTokens: nil, primarySource: .browserCookie, sources: [.browserCookie, .api], confidence: .low, isEstimated: false, message: "No OpenCode workspace reported usage", authSummary: "OpenCode cookie")
        } catch AuthError.missingCredentials {
            return ProviderSnapshot(providerID: providerID, status: .unauthenticated, usedTokens: nil, primarySource: .browserCookie, sources: [.browserCookie], confidence: .low, isEstimated: false, message: "OpenCode cookie not configured", authSummary: "OpenCode cookie")
        } catch {
            return ProviderSnapshot(providerID: providerID, status: .error, usedTokens: nil, primarySource: .browserCookie, sources: [.browserCookie, .api], confidence: .low, isEstimated: false, message: "OpenCode cookie usage failed", authSummary: "OpenCode cookie")
        }
    }

    static func snapshot(from object: [String: Any]) -> ProviderSnapshot {
        let rolling = RemoteJSON.findObject(in: object, keys: ["rollingUsage", "rolling_usage", "rolling", "rollingWindow"])
        let weekly = RemoteJSON.findObject(in: object, keys: ["weeklyUsage", "weekly_usage", "weekly"])
        let monthly = RemoteJSON.findObject(in: object, keys: ["monthlyUsage", "monthly_usage", "monthly"])
        let percent = RemoteJSON.percent(in: rolling ?? object)

        var rows = [UsageRow]()
        if let rolling {
            rows.append(RemoteJSON.row(key: "rolling", title: "Rolling Usage", iconName: "hourglass", object: rolling))
        }
        if let weekly {
            rows.append(RemoteJSON.row(key: "weekly", title: "Weekly Usage", iconName: "calendar", object: weekly))
        }
        if let monthly {
            rows.append(RemoteJSON.row(key: "monthly", title: "Monthly Usage", iconName: "calendar.badge.clock", object: monthly))
        }

        return ProviderSnapshot(
            providerID: .opencode,
            status: percent == nil && rows.isEmpty ? .noData : .ok,
            usedTokens: nil,
            unit: .tokens,
            usagePercent: percent,
            windowName: .session,
            resetAt: RemoteJSON.resetDate(in: rolling ?? object),
            refreshedAt: Date(),
            primarySource: .browserCookie,
            sources: [.browserCookie, .api],
            confidence: .medium,
            isEstimated: false,
            message: rows.isEmpty ? "Cookie usage returned no windows" : nil,
            authSummary: "OpenCode cookie",
            planName: RemoteJSON.planName(in: object, keys: ["plan", "tier", "subscription"]),
            usageRows: rows
        )
    }

    static func cookieHeader() throws -> String {
        if let cookie = ProcessInfo.processInfo.environment["TOKEN_MY_BAR_OPENCODE_COOKIE"], !cookie.isEmpty {
            return cookie.hasPrefix("Cookie:") ? String(cookie.dropFirst("Cookie:".count)).trimmingCharacters(in: .whitespaces) : cookie
        }
        if let imported = BrowserCookieImporter.cookieHeader(domain: "opencode.ai"), !imported.isEmpty {
            return imported
        }
        throw AuthError.missingCredentials
    }

    static let workspacesServerFunctionID = "def39973159c7f0483d8793a822b8dbb10d067e12c65455fcb4608459ba0234f"
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    /// Resolves candidate workspace IDs.
    ///
    /// Uses the configured override when present, otherwise calls the
    /// `workspaces` server function (`GET /_server?id=…` with an `X-Server-Id`
    /// header) and extracts every `wrk_…` identifier from the serialized JS
    /// response, preserving order.
    private static func workspaceIDs(cookie: String) async throws -> [String] {
        if let override = ProcessInfo.processInfo.environment["TOKEN_MY_BAR_OPENCODE_WORKSPACE_ID"], !override.isEmpty {
            let id = override.components(separatedBy: "/").last ?? override
            return [id]
        }

        let url = "https://opencode.ai/_server?id=\(workspacesServerFunctionID)"
        var request = serverRequest(url: url, cookie: cookie)
        request.setValue(workspacesServerFunctionID, forHTTPHeaderField: "X-Server-Id")
        request.setValue("server-fn:\(UUID().uuidString)", forHTTPHeaderField: "X-Server-Instance")
        let text = try await RemoteJSON.fetchText(request)
        let ids = workspaceIDs(in: text)
        guard !ids.isEmpty else { throw AuthError.parseFailed }
        return ids
    }

    static func workspaceIDs(in text: String) -> [String] {
        let pattern = "wrk_[A-Za-z0-9]+"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var seen = Set<String>()
        var ids = [String]()
        for match in regex.matches(in: text, range: range) {
            guard let r = Range(match.range, in: text) else { continue }
            let id = String(text[r])
            if seen.insert(id).inserted { ids.append(id) }
        }
        return ids
    }

    /// Fetches the workspace usage page and parses the embedded usage windows.
    private static func usageObject(cookie: String, workspaceID: String) async throws -> [String: Any] {
        var request = serverRequest(url: "https://opencode.ai/workspace/\(workspaceID)/go", cookie: cookie)
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        let text = try await RemoteJSON.fetchText(request)
        guard let object = parseUsagePage(text) else { throw AuthError.parseFailed }
        return object
    }

    /// Parses `rollingUsage`/`weeklyUsage`/`monthlyUsage` windows out of the
    /// serialized JS page into the dictionary shape `snapshot(from:)` expects.
    static func parseUsagePage(_ text: String) -> [String: Any]? {
        var result = [String: Any]()
        for (outputKey, sourceKey) in [
            ("rollingUsage", "rollingUsage"),
            ("weeklyUsage", "weeklyUsage"),
            ("monthlyUsage", "monthlyUsage"),
        ] {
            guard let body = windowBody(for: sourceKey, in: text) else { continue }
            var window = [String: Any]()
            if let percent = number("usagePercent", in: body) { window["usagePercent"] = percent }
            if let reset = number("resetInSec", in: body) { window["resetInSec"] = reset }
            if !window.isEmpty { result[outputKey] = window }
        }
        return result.isEmpty ? nil : result
    }

    /// Captures the `{ … }` body of a `key…={ … }` assignment, skipping decoy
    /// occurrences like `monthlyUsage:0,` that are not object assignments.
    private static func windowBody(for key: String, in text: String) -> String? {
        let pattern = "\(key)[^=}]*=\\s*\\{([^}]*)\\}"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let bodyRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[bodyRange])
    }

    private static func number(_ field: String, in body: String) -> Double? {
        let pattern = "\(field)\\s*:\\s*([0-9]+(?:\\.[0-9]+)?)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        guard let match = regex.firstMatch(in: body, range: range),
              let valueRange = Range(match.range(at: 1), in: body) else { return nil }
        return Double(body[valueRange])
    }

    private static func serverRequest(url: String, cookie: String) -> URLRequest {
        var request = URLRequest(url: URL(string: url)!, timeoutInterval: 15)
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://opencode.ai", forHTTPHeaderField: "Origin")
        request.setValue("https://opencode.ai", forHTTPHeaderField: "Referer")
        return request
    }
}
