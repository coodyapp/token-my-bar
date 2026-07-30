import Foundation

public struct LocalJSONLUsage: Equatable, Sendable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let reasoningTokens: Int
    public let cacheReadTokens: Int
    public let cacheWriteTokens: Int
    public let totalFallbackTokens: Int
    public let sessionTokens: Int
    public let weeklyTokens: Int
    public let sonnetTokens: Int
    public let sampleCount: Int
    public let fileCount: Int
    public let lastUpdatedAt: Date?

    public var totalTokens: Int {
        clampedSum(inputTokens, outputTokens, reasoningTokens, cacheReadTokens, cacheWriteTokens, totalFallbackTokens)
    }

    public var primaryTokens: Int {
        sessionTokens
    }
}

public struct LocalJSONLUsageProvider: ProviderClient {
    public let providerID: ProviderID
    private let roots: [URL]
    private let authSummary: String
    private let maxFiles: Int
    private let maxFileBytes: UInt64
    private let chunkSize = 64 * 1024
    private let maxLineBytes = 2 * 1024 * 1024

    public init(
        providerID: ProviderID,
        roots: [URL],
        authSummary: String,
        maxFiles: Int = 200,
        maxFileBytes: UInt64 = 20 * 1024 * 1024
    ) {
        self.providerID = providerID
        self.roots = roots
        self.authSummary = authSummary
        self.maxFiles = maxFiles
        self.maxFileBytes = maxFileBytes
    }

    public static func claude() -> LocalJSONLUsageProvider {
        LocalJSONLUsageProvider(
            providerID: .claudeCode,
            roots: [FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/projects", isDirectory: true)],
            authSummary: "Local Claude logs / no network auth"
        )
    }

    public static func codex() -> LocalJSONLUsageProvider {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let override = ProcessInfo.processInfo.environment["TOKEN_MY_BAR_CODEX_HOME"]
        let base = if let override, !override.isEmpty {
            URL(fileURLWithPath: override, isDirectory: true)
        } else {
            home.appendingPathComponent(".codex", isDirectory: true)
        }
        return LocalJSONLUsageProvider(
            providerID: .codex,
            roots: [base.appendingPathComponent("sessions", isDirectory: true), base],
            authSummary: "Local Codex logs / no network auth"
        )
    }

    public func snapshot() async -> ProviderSnapshot {
        do {
            let usage = try scanUsage()
            return ProviderSnapshot(
                providerID: providerID,
                status: usage.primaryTokens > 0 ? .ok : .noData,
                usedTokens: usage.primaryTokens > 0 ? usage.primaryTokens : nil,
                unit: .tokens,
                windowName: .session,
                refreshedAt: Date(),
                primarySource: .localLog,
                sources: [.localLog],
                confidence: usage.primaryTokens > 0 ? .medium : .low,
                isEstimated: true,
                message: usage.primaryTokens > 0
                    ? "Local samples: \(usage.sampleCount)"
                    : "Local logs found, but no token usage yet",
                authSummary: authSummary,
                // Rows of zeros would read as real data downstream and displace
                // good cached numbers, so an empty scan reports nothing at all.
                usageRows: usage.totalTokens > 0 ? usage.rows(for: providerID) : []
            )
        } catch {
            return ProviderSnapshot(
                providerID: providerID,
                status: .noData,
                usedTokens: nil,
                primarySource: .localLog,
                confidence: .low,
                isEstimated: true,
                message: "Local logs not found",
                authSummary: authSummary
            )
        }
    }

    public func scanUsage(now: Date = Date()) throws -> LocalJSONLUsage {
        let files = discoverJSONLFiles(now: now)
        guard !files.isEmpty else { throw CocoaError(.fileNoSuchFile) }

        var totals = MutableUsageTotals()
        var seenIDs = Set<String>()
        var lastUpdatedAt: Date?

        for file in files {
            if let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
                lastUpdatedAt = maxDate(lastUpdatedAt, modified)
            }
            // One unreadable or since-deleted log must not sink the whole scan
            // and report "Local logs not found" over hundreds of valid files.
            try? scanFile(file, totals: &totals, seenIDs: &seenIDs, now: now)
        }

        return LocalJSONLUsage(
            inputTokens: totals.input,
            outputTokens: totals.output,
            reasoningTokens: totals.reasoning,
            cacheReadTokens: totals.cacheRead,
            cacheWriteTokens: totals.cacheWrite,
            totalFallbackTokens: totals.totalFallback,
            sessionTokens: totals.session,
            weeklyTokens: totals.weekly,
            sonnetTokens: totals.sonnet,
            sampleCount: totals.samples,
            fileCount: files.count,
            lastUpdatedAt: lastUpdatedAt
        )
    }

    /// Discovers `.jsonl` files under `roots`, always including every file
    /// modified within the 7-day weekly window (so the weekly total is never
    /// silently truncated by `maxFiles`) and capping only files older than
    /// that window, which can no longer affect session or weekly totals.
    private func discoverJSONLFiles(now: Date = Date()) -> [URL] {
        var files: [(url: URL, modified: Date)] = []
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]

        for root in roots where FileManager.default.fileExists(atPath: root.path) {
            if root.pathExtension == "jsonl" {
                guard let values = try? root.resourceValues(forKeys: keys) else { continue }
                if values.isRegularFile == true, UInt64(values.fileSize ?? 0) <= maxFileBytes {
                    files.append((root, values.contentModificationDate ?? .distantPast))
                }
                continue
            }

            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let file as URL in enumerator where file.pathExtension == "jsonl" {
                guard let values = try? file.resourceValues(forKeys: keys),
                      values.isRegularFile == true,
                      UInt64(values.fileSize ?? 0) <= maxFileBytes
                else { continue }
                files.append((file, values.contentModificationDate ?? .distantPast))
            }
        }

        var seen = Set<String>()
        let deduped = files.filter { item in
            let path = item.url.standardizedFileURL.path
            return seen.insert(path).inserted
        }

        let weeklyCutoff = now.addingTimeInterval(-7 * 24 * 60 * 60)
        let recent = deduped.filter { $0.modified >= weeklyCutoff }.sorted { $0.modified > $1.modified }
        let older = deduped.filter { $0.modified < weeklyCutoff }.sorted { $0.modified > $1.modified }
        let olderBudget = max(0, maxFiles - recent.count)

        return (recent + older.prefix(olderBudget)).map(\.url)
    }

    private func scanFile(_ file: URL, totals: inout MutableUsageTotals, seenIDs: inout Set<String>, now: Date) throws {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }

        var buffer = Data()
        while true {
            let chunk = try handle.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty { break }
            buffer.append(chunk)

            while let newlineRange = buffer.firstRange(of: Data([0x0A])) {
                let line = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
                buffer.removeSubrange(buffer.startIndex..<newlineRange.upperBound)
                processLine(line, totals: &totals, seenIDs: &seenIDs, now: now)
            }

            if buffer.count > maxLineBytes {
                buffer.removeAll(keepingCapacity: true)
            }
        }

        if !buffer.isEmpty {
            processLine(buffer, totals: &totals, seenIDs: &seenIDs, now: now)
        }
    }

    private func processLine(_ line: Data, totals: inout MutableUsageTotals, seenIDs: inout Set<String>, now: Date) {
        guard !line.isEmpty,
              line.count <= maxLineBytes,
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any]
        else { return }
        let id = Self.messageID(in: object)
        if let id, seenIDs.contains(id) { return }
        guard let usage = Self.firstUsageObject(in: object) else { return }
        let parsed = Self.parseUsage(usage)
        guard !parsed.isZero else { return }
        if let id { seenIDs.insert(id) }
        totals.add(
            parsed,
            timestamp: Self.timestamp(in: object),
            model: Self.model(in: object),
            now: now
        )
    }

    private static func firstUsageObject(in value: Any) -> [String: Any]? {
        if let object = value as? [String: Any] {
            if let usage = object["usage"] as? [String: Any] { return usage }
            for child in object.values {
                if let found = firstUsageObject(in: child) { return found }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let found = firstUsageObject(in: child) { return found }
            }
        }
        return nil
    }

    /// Claude Code writes one record per assistant content block, each repeating
    /// the same `message.id` and the same *cumulative* usage under a fresh
    /// top-level `uuid`. The message id therefore has to win, or those repeats
    /// slip past the dedupe and inflate every total.
    private static func messageID(in object: [String: Any]) -> String? {
        if let message = object["message"] as? [String: Any], let id = message["id"] as? String { return id }
        if let id = object["id"] as? String { return id }
        if let id = object["uuid"] as? String { return id }
        return nil
    }

    private static func model(in object: [String: Any]) -> String? {
        if let model = object["model"] as? String { return model }
        if let message = object["message"] as? [String: Any], let model = message["model"] as? String { return model }
        return nil
    }

    private static func timestamp(in object: [String: Any]) -> Date? {
        if let value = object["timestamp"] as? String {
            // Real logs (Claude Code, Codex) write fractional seconds, e.g.
            // "2026-07-04T03:10:20.906Z"; a bare ISO8601DateFormatter rejects
            // them. Reuse the fractional-aware parser so recent entries land in
            // the session/weekly windows instead of being silently dropped.
            return RemoteJSON.parseISO8601(value)
        }
        if let value = object["timestamp"] as? Double {
            return Date(timeIntervalSince1970: value > 10_000_000_000 ? value / 1000 : value)
        }
        if let value = object["timestamp"] as? Int {
            let double = Double(value)
            return Date(timeIntervalSince1970: double > 10_000_000_000 ? double / 1000 : double)
        }
        return nil
    }

    private static func parseUsage(_ usage: [String: Any]) -> ParsedUsage {
        ParsedUsage(
            input: intValue(usage, keys: ["input_tokens", "inputTokens", "prompt_tokens", "promptTokens", "input"]),
            output: intValue(usage, keys: ["output_tokens", "outputTokens", "completion_tokens", "completionTokens", "output"]),
            reasoning: intValue(usage, keys: ["reasoning_tokens", "reasoningTokens", "tokens_reasoning"]),
            cacheRead: intValue(usage, keys: ["cache_read_input_tokens", "cache_read_tokens", "cacheReadTokens", "cacheRead", "cache_read"]),
            cacheWrite: intValue(usage, keys: ["cache_creation_input_tokens", "cache_creation_tokens", "cacheWriteTokens", "cacheWrite", "cache_write_tokens", "cache_write"]),
            totalFallback: intValue(usage, keys: ["total_tokens", "totalTokens", "token_count", "tokenCount", "tokens"])
        )
    }

    /// Upper bound for a single token count. Logs in the scanned directories are
    /// also written by third-party tools, so a corrupt value (`1e300`, a 20-digit
    /// integer, a negative) must neither trap `Int(_:)` nor overflow the totals.
    static let maxTokenValue = 1_000_000_000_000

    private static func intValue(_ object: [String: Any], keys: [String]) -> Int {
        for key in keys {
            if let value = object[key] as? Int { return clampTokens(Double(value)) }
            if let value = object[key] as? Int64 { return clampTokens(Double(value)) }
            if let value = object[key] as? Double { return clampTokens(value) }
            if let value = object[key] as? String, let parsed = Double(value) { return clampTokens(parsed) }
        }
        return 0
    }

    private static func clampTokens(_ value: Double) -> Int {
        guard value.isFinite, value > 0 else { return 0 }
        return value >= Double(maxTokenValue) ? maxTokenValue : Int(value)
    }
}

private struct MutableUsageTotals {
    var input = 0
    var output = 0
    var reasoning = 0
    var cacheRead = 0
    var cacheWrite = 0
    var totalFallback = 0
    var session = 0
    var weekly = 0
    var sonnet = 0
    var samples = 0

    mutating func add(_ usage: ParsedUsage, timestamp: Date?, model: String?, now: Date) {
        let total = usage.primary
        input.clampedAdd(usage.input)
        output.clampedAdd(usage.output)
        reasoning.clampedAdd(usage.reasoning)
        cacheRead.clampedAdd(usage.cacheRead)
        cacheWrite.clampedAdd(usage.cacheWrite)
        totalFallback.clampedAdd(usage.totalFallback)
        if let timestamp {
            if timestamp >= now.addingTimeInterval(-5 * 60 * 60) { session.clampedAdd(total) }
            if timestamp >= now.addingTimeInterval(-7 * 24 * 60 * 60) { weekly.clampedAdd(total) }
        }
        if model?.localizedCaseInsensitiveContains("sonnet") == true {
            sonnet.clampedAdd(total)
        }
        samples += 1
    }
}

private struct ParsedUsage {
    let input: Int
    let output: Int
    let reasoning: Int
    let cacheRead: Int
    let cacheWrite: Int
    let totalFallback: Int

    var total: Int {
        let componentTotal = clampedSum(input, output, reasoning, cacheRead, cacheWrite)
        return componentTotal > 0 ? componentTotal : totalFallback
    }

    var primary: Int {
        let primaryTotal = clampedSum(input, output, reasoning)
        return primaryTotal > 0 ? primaryTotal : totalFallback
    }

    var isZero: Bool {
        input == 0 && output == 0 && reasoning == 0 && cacheRead == 0 && cacheWrite == 0 && totalFallback == 0
    }
}

/// Saturating sum: per-value clamping alone still leaves the running totals able
/// to overflow across a very large corrupt log, and an overflow here traps.
private func clampedSum(_ values: Int...) -> Int {
    values.reduce(0) { partial, value in
        let (sum, overflow) = partial.addingReportingOverflow(value)
        return overflow ? .max : sum
    }
}

private extension Int {
    mutating func clampedAdd(_ value: Int) {
        self = clampedSum(self, value)
    }
}

private func maxDate(_ lhs: Date?, _ rhs: Date) -> Date {
    guard let lhs else { return rhs }
    return lhs > rhs ? lhs : rhs
}

extension LocalJSONLUsage {
    func rows(for providerID: ProviderID) -> [UsageRow] {
        var rows = [
            UsageRow(
                key: "session",
                title: "Session",
                subtitle: "Last 5h local tokens",
                value: Format.count(sessionTokens),
                unit: .tokens
            ),
            UsageRow(
                key: "weekly",
                title: "Weekly",
                subtitle: "Last 7d local tokens",
                value: Format.count(weeklyTokens),
                unit: .tokens
            ),
        ]

        if providerID == .claudeCode {
            rows.append(UsageRow(
                key: "sonnet",
                title: "Sonnet only",
                subtitle: "Local Sonnet model tokens",
                value: Format.count(sonnetTokens),
                unit: .tokens
            ))
        }

        rows.append(UsageRow(
            key: "cache-reasoning",
            title: "Cache + reasoning",
            subtitle: "All time, not windowed like Session/Weekly",
            value: Format.count(clampedSum(cacheReadTokens, cacheWriteTokens, reasoningTokens)),
            unit: .tokens
        ))

        return rows
    }
}
