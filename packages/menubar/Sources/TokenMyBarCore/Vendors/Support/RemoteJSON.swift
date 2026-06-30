import Foundation

enum RemoteJSON {
    static func request(url: String) -> URLRequest {
        guard let url = URL(string: url) else {
            var req = URLRequest(url: URL(string: "https://localhost")!)
            req.timeoutInterval = 0.1
            return req
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    static func fetchObject(_ request: URLRequest, session: URLSession = .shared) async throws -> [String: Any] {
        let data = try await fetchData(request, session: session)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthError.parseFailed
        }
        return object
    }

    static func fetchText(_ request: URLRequest, session: URLSession = .shared) async throws -> String {
        let data = try await fetchData(request, session: session)
        return String(decoding: data, as: UTF8.self)
    }

    /// Maximum nesting depth for recursive key lookups. Bounds work on hostile
    /// or deeply nested payloads and avoids matching far-away unrelated keys.
    private static let maxSearchDepth = 8

    static func findObject(in value: Any, keys: [String], depth: Int = 0) -> [String: Any]? {
        guard depth <= maxSearchDepth else { return nil }
        if let object = value as? [String: Any] {
            for key in keys {
                if let child = object[key] as? [String: Any] { return child }
            }
            for child in object.values {
                if let found = findObject(in: child, keys: keys, depth: depth + 1) { return found }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let found = findObject(in: child, keys: keys, depth: depth + 1) { return found }
            }
        }
        return nil
    }

    static func findString(in value: Any, keys: [String], depth: Int = 0) -> String? {
        guard depth <= maxSearchDepth else { return nil }
        if let object = value as? [String: Any] {
            for key in keys {
                if let value = object[key] as? String, !value.isEmpty { return value }
            }
            for child in object.values {
                if let found = findString(in: child, keys: keys, depth: depth + 1) { return found }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let found = findString(in: child, keys: keys, depth: depth + 1) { return found }
            }
        }
        return nil
    }

    /// Returns a usage percentage normalized to the 0...100 range.
    ///
    /// Providers report percentages as either 0...100 (Claude `utilization`,
    /// OpenCode `usagePercent`) or as a 0...1 fraction. Values in 0...1 are
    /// treated as fractions and scaled, everything else is clamped into 0...100.
    ///
    /// Some providers (Codex) report percent **remaining** rather than used.
    /// Pass `remaining: true` to invert into the used percentage the UI expects,
    /// so every vendor counts up 0→100 with matching bar colors.
    static func percent(in object: [String: Any], remaining: Bool = false) -> Double? {
        guard let raw = double(object, keys: [
            "usagePercent", "usage_percent", "percent", "percentUsed",
            "used_percent", "utilization", "usedPercent",
        ]) else { return nil }
        let used = normalizePercent(raw)
        return remaining ? 100 - used : used
    }

    static func normalizePercent(_ raw: Double) -> Double {
        let scaled = raw > 0 && raw <= 1 ? raw * 100 : raw
        return min(max(scaled, 0), 100)
    }

    static func resetDate(in object: [String: Any], now: Date = Date()) -> Date? {
        if let seconds = double(object, keys: [
            "resetInSec", "resetInSeconds", "reset_in_sec", "resetSeconds",
            "resetsInSec", "resetsInSeconds", "reset_sec", "secondsUntilReset",
            "reset_after_seconds", "resetAfterSeconds", "resets_in_seconds",
            "resetIn", "resetSec",
        ]) {
            return now.addingTimeInterval(seconds)
        }
        if let timestamp = double(object, keys: ["resetAt", "reset_at", "resetsAt", "resets_at"]) {
            return Date(timeIntervalSince1970: timestamp > 10_000_000_000 ? timestamp / 1000 : timestamp)
        }
        if let iso = string(object, keys: ["resetAt", "reset_at", "resetsAt", "resets_at", "renewAt"]),
           let date = parseISO8601(iso) {
            return date
        }
        return nil
    }

    static func parseISO8601(_ value: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }

    static func resetSubtitle(in object: [String: Any], now: Date = Date()) -> String? {
        guard let reset = resetDate(in: object, now: now) else { return nil }
        return resetSubtitle(for: reset, now: now)
    }

    static func resetSubtitle(for reset: Date, now: Date = Date()) -> String {
        let minutes = max(0, Int(reset.timeIntervalSince(now) / 60))
        if minutes >= 24 * 60 { return "Resets in \(minutes / (24 * 60))d \((minutes % (24 * 60)) / 60)h" }
        if minutes >= 60 { return "Resets in \(minutes / 60)h \(minutes % 60)m" }
        return "Resets in \(minutes)m"
    }

    static func row(key: String, title: String, iconName: String? = nil, object: [String: Any], now: Date = Date(), idleDetail: String? = nil, remaining: Bool = false) -> UsageRow {
        let percent = percent(in: object, remaining: remaining) ?? 0
        let resetSub = resetSubtitle(in: object, now: now)
        return UsageRow(
            key: key,
            title: title,
            value: "\(Int(percent.rounded()))%",
            detail: resetSub ?? idleDetail,
            iconName: iconName,
            percent: percent,
            unit: .tokens
        )
    }

    /// Extracts a human-friendly plan/tier label, e.g. `plan_type: "pro"` -> "Pro".
    static func planName(in object: Any, keys: [String]) -> String? {
        guard let raw = findString(in: object, keys: keys) else { return nil }
        let cleaned = raw.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        return cleaned
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// One automatic retry (2 attempts total) for transient failures.
    private static let maxRetries = 1

    /// HTTP statuses worth retrying: request timeout, rate limit, and 5xx.
    private static func isTransient(_ status: Int) -> Bool {
        status == 408 || status == 429 || (500..<600).contains(status)
    }

    /// Fetches with a status-aware error and a bounded retry on transient
    /// failures (5xx/429/408 and network errors). Non-2xx responses throw
    /// `AuthError.http(status)` so providers can map 401/403 to a sign-in
    /// state instead of a generic error. 4xx (except 408/429) never retries.
    private static func fetchData(_ request: URLRequest, session: URLSession = .shared, attempt: Int = 0) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw AuthError.parseFailed }
            if (200..<300).contains(http.statusCode) { return data }
            guard isTransient(http.statusCode), attempt < maxRetries else {
                throw AuthError.http(http.statusCode)
            }
        } catch let error as AuthError {
            throw error
        } catch {
            // Network-level failure (URLError etc.) — retry while attempts remain.
            guard attempt < maxRetries else { throw error }
        }
        try? await Task.sleep(nanoseconds: UInt64((attempt + 1) * 500) * 1_000_000)
        return try await fetchData(request, session: session, attempt: attempt + 1)
    }

    private static func double(_ object: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = object[key] as? Double { return value }
            if let value = object[key] as? Int { return Double(value) }
            if let value = object[key] as? String, let parsed = Double(value) { return parsed }
        }
        return nil
    }

    private static func string(_ object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String, !value.isEmpty { return value }
        }
        return nil
    }
}
