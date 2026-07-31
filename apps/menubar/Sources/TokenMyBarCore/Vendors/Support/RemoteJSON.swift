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

    /// Returns a usage percentage clamped to the 0...100 range.
    ///
    /// Every provider reports percent *used* on a 0...100 scale (Codex
    /// `used_percent`, Claude `utilization`, OpenCode `usagePercent`) —
    /// verified against live payloads. Small values pass through unscaled:
    /// Codex sends `used_percent: 1` meaning 1%, so a 0...1 "fraction"
    /// heuristic would misread it as 100%.
    ///
    /// Only keys that name the direction are accepted. A bare `percent` could
    /// equally be percent *remaining* — the vendor dashboards show that number —
    /// and guessing wrong inverts the reading, which is worse than reporting
    /// nothing and saying so.
    static func percent(in object: [String: Any]) -> Double? {
        guard let raw = double(object, keys: [
            "usagePercent", "usage_percent", "percentUsed",
            "used_percent", "utilization", "usedPercent",
        ]) else { return nil }
        return normalizePercent(raw)
    }

    static func normalizePercent(_ raw: Double) -> Double? {
        // Reject non-finite input: a malformed payload can encode percent as
        // "nan"/"inf", and a NaN survives min/max clamping (all comparisons
        // are false), later trapping Int(percent.rounded()). Treat as no data.
        guard raw.isFinite else { return nil }
        return min(max(raw, 0), 100)
    }

    static func resetDate(in object: [String: Any], now: Date = Date()) -> Date? {
        // Absolute timestamps win over countdown fields: Codex sends both, and
        // its reset_after_seconds is the static window length (always 5h/7d),
        // not the time actually left.
        if let timestamp = double(object, keys: ["resetAt", "reset_at", "resetsAt", "resets_at"]) {
            return Date(timeIntervalSince1970: timestamp > 10_000_000_000 ? timestamp / 1000 : timestamp)
        }
        if let iso = string(object, keys: ["resetAt", "reset_at", "resetsAt", "resets_at", "renewAt"]),
           let date = parseISO8601(iso) {
            return date
        }
        if let seconds = double(object, keys: [
            "resetInSec", "resetInSeconds", "reset_in_sec", "resetSeconds",
            "resetsInSec", "resetsInSeconds", "reset_sec", "secondsUntilReset",
            "reset_after_seconds", "resetAfterSeconds", "resets_in_seconds",
            "resetIn", "resetSec",
        ]) {
            return now.addingTimeInterval(seconds)
        }
        return nil
    }

    static func parseISO8601(_ value: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }

    /// The first window the vendor sent whose percentage this build could not
    /// read. Providers report it as an error: a renamed field must not surface
    /// as a confident reading.
    static func unreadableWindow(in rows: [UsageRow]) -> UsageRow? {
        rows.first { $0.percent == nil }
    }

    /// Every nested window whose key begins with one of `prefixes`, in sorted key
    /// order. Vendors add per-model limits over time — Claude grew a "Fable"
    /// weekly window — and enumerating them means a new one shows up instead of
    /// being silently dropped by a hardcoded key list.
    static func windows(
        in object: Any,
        prefixes: [String],
        excluding: Set<String> = [],
        depth: Int = 0
    ) -> [(key: String, object: [String: Any])] {
        guard depth < maxSearchDepth, let dictionary = object as? [String: Any] else { return [] }
        var found: [(key: String, object: [String: Any])] = []
        for (key, value) in dictionary {
            guard let window = value as? [String: Any] else { continue }
            if !excluding.contains(key), prefixes.contains(where: { key.hasPrefix($0) }), key.count > (prefixes.first(where: { key.hasPrefix($0) })?.count ?? 0) {
                found.append((key, window))
            }
            found.append(contentsOf: windows(in: window, prefixes: prefixes, excluding: excluding, depth: depth + 1))
        }
        return found.sorted { $0.key < $1.key }
    }

    /// Builds a usage row for one window.
    ///
    /// A window the vendor sent but whose percent field this build does not
    /// recognise yields `percent == nil`, never 0: reporting a renamed field as
    /// "0% used" tells the user they have a full tank when they may have none.
    /// Callers surface that as an error rather than a reading.
    static func row(key: String, title: String, iconName: String? = nil, object: [String: Any], now: Date = Date(), idleDetail: String? = nil) -> UsageRow {
        let percent = percent(in: object)
        return UsageRow(
            key: key,
            title: title,
            value: percent.map { "\(Int($0.rounded()))%" } ?? "—",
            detail: idleDetail,
            iconName: iconName,
            resetAt: resetDate(in: object, now: now),
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
        // Bail before issuing a (or a retry) request if the enclosing refresh
        // Task was cancelled/superseded, so a closed refresh never fires an
        // extra network call.
        try Task.checkCancellation()
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
