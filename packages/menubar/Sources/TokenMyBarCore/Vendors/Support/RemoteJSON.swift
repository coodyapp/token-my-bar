import Foundation

enum RemoteJSON {
    static func request(url: String) -> URLRequest {
        var request = URLRequest(url: URL(string: url)!, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    static func fetchObject(_ request: URLRequest) async throws -> [String: Any] {
        let data = try await fetchData(request)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthError.parseFailed
        }
        return object
    }

    static func fetchText(_ request: URLRequest) async throws -> String {
        let data = try await fetchData(request)
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
    /// Providers report percentages as either 0...100 (Codex `used_percent`,
    /// Claude `utilization`, OpenCode `usagePercent`) or as a 0...1 fraction.
    /// Values in 0...1 are treated as fractions and scaled, everything else is
    /// clamped into 0...100.
    static func percent(in object: [String: Any]) -> Double? {
        guard let raw = double(object, keys: [
            "usagePercent", "usage_percent", "percent", "percentUsed",
            "used_percent", "utilization", "usedPercent",
        ]) else { return nil }
        return normalizePercent(raw)
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

    static func row(key: String, title: String, iconName: String? = nil, object: [String: Any], now: Date = Date()) -> UsageRow {
        let percent = percent(in: object) ?? 0
        return UsageRow(
            key: key,
            title: title,
            value: "\(Int(percent.rounded()))%",
            detail: resetSubtitle(in: object, now: now),
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

    static func parseJavaScriptObject(_ text: String) -> [String: Any]? {
        guard let first = text.firstIndex(of: "{"), let last = text.lastIndex(of: "}") else { return nil }
        let json = String(text[first...last])
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func fetchData(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AuthError.parseFailed
        }
        return data
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
