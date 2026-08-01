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
    private let cacheURL: URL?
    private let chunkSize = 64 * 1024
    private let maxLineBytes = 2 * 1024 * 1024

    /// `cacheURL` enables the per-file incremental cache; `nil` always does a
    /// full scan, which is what callers pointed at throwaway directories want.
    public init(
        providerID: ProviderID,
        roots: [URL],
        authSummary: String,
        maxFiles: Int = 200,
        cacheURL: URL? = nil
    ) {
        self.providerID = providerID
        self.roots = roots
        self.authSummary = authSummary
        self.maxFiles = maxFiles
        self.cacheURL = cacheURL
    }

    /// Lives beside the snapshot cache, one file per vendor.
    static func defaultCacheURL(for providerID: ProviderID) -> URL {
        SnapshotStore.defaultURL()
            .deletingLastPathComponent()
            .appendingPathComponent("local-scan-\(providerID.rawValue).json")
    }

    public static func claude() -> LocalJSONLUsageProvider {
        LocalJSONLUsageProvider(
            providerID: .claudeCode,
            roots: [FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/projects", isDirectory: true)],
            authSummary: "Local Claude logs / no network auth",
            cacheURL: defaultCacheURL(for: .claudeCode)
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
            authSummary: "Local Codex logs / no network auth",
            cacheURL: defaultCacheURL(for: .codex)
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

    /// Scans every discovered log, replaying files from the on-disk per-file
    /// cache whenever that provably cannot change the answer, and rewrites the
    /// cache for the next refresh.
    public func scanUsage(now: Date = Date()) throws -> LocalJSONLUsage {
        let files = discoverJSONLFiles(now: now)
        guard !files.isEmpty else { throw CocoaError(.fileNoSuchFile) }

        let cache = loadCache()
        var nextCache: [String: FileScanCacheEntry] = [:]
        var totals = MutableUsageTotals()
        var seenIDs = Set<String>()
        var lastUpdatedAt: Date?

        for file in files {
            lastUpdatedAt = maxDate(lastUpdatedAt, file.modified)
            let key = file.url.standardizedFileURL.path

            // Cached totals count every message in their file, so replaying an
            // entry that shares ids with an already-counted file would count
            // those twice; such a file is parsed instead.
            if let entry = cache[key], entry.replays(file), seenIDs.isDisjoint(with: entry.ids) {
                totals.add(entry.totals)
                seenIDs.formUnion(entry.ids)
                nextCache[key] = entry
                continue
            }

            // One unreadable or since-deleted log must not sink the whole scan
            // and report "Local logs not found" over hundreds of valid files.
            guard let scan = autoreleasepool(invoking: { try? scanFile(file.url, seenIDs: seenIDs) })
            else { continue }
            totals.add(scan.novel)
            seenIDs.formUnion(scan.ids)
            // A log that collides on ids is re-parsed on every scan; keeping its
            // entry while the bytes are unchanged leaves the cache file itself
            // untouched, so no write follows.
            if let existing = cache[key], existing.replays(file) {
                nextCache[key] = existing
            } else {
                nextCache[key] = FileScanCacheEntry(file, scan: scan, now: now)
            }
        }

        if nextCache != cache { saveCache(nextCache) }

        return LocalJSONLUsage(
            inputTokens: totals.input,
            outputTokens: totals.output,
            reasoningTokens: totals.reasoning,
            cacheReadTokens: totals.cacheRead,
            cacheWriteTokens: totals.cacheWrite,
            totalFallbackTokens: totals.totalFallback,
            sessionTokens: totals.tokens(since: Self.sessionCutoff(from: now)),
            weeklyTokens: totals.tokens(since: Self.weeklyCutoff(from: now)),
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
    ///
    /// Size is deliberately not a filter: skipping a large file drops a whole
    /// session's usage. The chunked reader and the per-line bound keep even a
    /// pathological file cheap to walk.
    private func discoverJSONLFiles(now: Date = Date()) -> [DiscoveredFile] {
        var files: [DiscoveredFile] = []
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]

        for root in roots where FileManager.default.fileExists(atPath: root.path) {
            if root.pathExtension == "jsonl" {
                guard let values = try? root.resourceValues(forKeys: keys) else { continue }
                if values.isRegularFile == true {
                    files.append(DiscoveredFile(url: root, values: values))
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
                      values.isRegularFile == true
                else { continue }
                files.append(DiscoveredFile(url: file, values: values))
            }
        }

        var seen = Set<String>()
        let deduped = files.filter { item in
            let path = item.url.standardizedFileURL.path
            return seen.insert(path).inserted
        }

        let cutoff = Self.weeklyCutoff(from: now)
        let recent = deduped.filter { $0.modified >= cutoff }.sorted { $0.modified > $1.modified }
        let older = deduped.filter { $0.modified < cutoff }.sorted { $0.modified > $1.modified }
        let olderBudget = max(0, maxFiles - recent.count)

        return recent + older.prefix(olderBudget)
    }

    static func weeklyCutoff(from now: Date) -> Date {
        now.addingTimeInterval(-7 * 24 * 60 * 60)
    }

    static func sessionCutoff(from now: Date) -> Date {
        now.addingTimeInterval(-5 * 60 * 60)
    }

    private func scanFile(_ file: URL, seenIDs: Set<String>) throws -> FileScan {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }

        var scan = FileScan()
        var buffer = Data()
        while true {
            let chunk = try handle.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty { break }
            buffer.append(chunk)

            // Every parsed line strands autoreleased Foundation objects that a
            // menu bar app only drains at the end of the run loop turn, which is
            // one whole scan later: 347 MB peak over a real 130 MB log directory.
            autoreleasepool {
                while let newlineRange = buffer.firstRange(of: Data([0x0A])) {
                    let line = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
                    buffer.removeSubrange(buffer.startIndex..<newlineRange.upperBound)
                    processLine(line, scan: &scan, seenIDs: seenIDs)
                }
            }

            if buffer.count > maxLineBytes {
                buffer.removeAll(keepingCapacity: true)
            }
        }

        if !buffer.isEmpty {
            autoreleasepool { processLine(buffer, scan: &scan, seenIDs: seenIDs) }
        }
        return scan
    }

    private func processLine(_ line: Data, scan: inout FileScan, seenIDs: Set<String>) {
        guard !line.isEmpty,
              line.count <= maxLineBytes,
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any]
        else { return }
        let id = Self.messageID(in: object)
        if let id, scan.ids.contains(id) { return }
        guard let usage = Self.firstUsageObject(in: object) else { return }
        let parsed = Self.parseUsage(usage)
        guard !parsed.isZero else { return }
        let timestamp = Self.timestamp(in: object)
        let model = Self.model(in: object)
        scan.isolated.add(parsed, timestamp: timestamp, model: model)
        // A resumed or forked session replays another file's messages verbatim:
        // the cached per-file totals above have to count them, this scan's
        // running totals below must not.
        if let id {
            scan.ids.insert(id)
            if seenIDs.contains(id) { return }
        }
        scan.novel.add(parsed, timestamp: timestamp, model: model)
    }

    /// A cache that is missing, unreadable or stale-format is a cache miss, never
    /// a failed scan.
    private func loadCache() -> [String: FileScanCacheEntry] {
        guard let cacheURL,
              let data = try? Data(contentsOf: cacheURL),
              let entries = try? JSONDecoder().decode([String: FileScanCacheEntry].self, from: data)
        else { return [:] }
        return entries
    }

    /// Entries are written only for the files of the current scan, so logs the
    /// user deleted or that aged out of `maxFiles` drop off instead of piling up.
    private func saveCache(_ entries: [String: FileScanCacheEntry]) {
        guard let cacheURL, let data = try? JSONEncoder().encode(entries) else { return }
        let directory = cacheURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        // Same temp-write + rename as the snapshot cache: a torn file would be
        // read back as corrupt on the next refresh.
        let tempURL = directory.appendingPathComponent(".\(cacheURL.lastPathComponent).tmp")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        guard FileManager.default.createFile(
            atPath: tempURL.path,
            contents: data,
            attributes: [.posixPermissions: 0o600]
        ) else { return }

        if FileManager.default.fileExists(atPath: cacheURL.path) {
            guard (try? FileManager.default.replaceItemAt(cacheURL, withItemAt: tempURL)) != nil else { return }
        } else {
            guard (try? FileManager.default.moveItem(at: tempURL, to: cacheURL)) != nil else { return }
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cacheURL.path)
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

private struct DiscoveredFile {
    let url: URL
    let modified: Date
    let size: UInt64

    init(url: URL, values: URLResourceValues) {
        self.url = url
        self.modified = values.contentModificationDate ?? .distantPast
        self.size = UInt64(values.fileSize ?? 0)
    }
}

/// One file's contribution, split because the two answers differ whenever the
/// file shares message ids with a file already scanned.
private struct FileScan {
    /// This file on its own, which is what may be cached and replayed later.
    var isolated = MutableUsageTotals()
    /// Only the ids this scan had not already counted in an earlier file.
    var novel = MutableUsageTotals()
    var ids = Set<String>()
}

/// A file's parse result, persisted so an unchanged log is not re-read on every
/// refresh — this scan runs as often as once a minute, for weeks.
private struct FileScanCacheEntry: Codable, Equatable {
    let size: UInt64
    /// Epoch seconds rather than `Date`: compared for exact equality, so it must
    /// round-trip through JSON bit for bit.
    let modified: Double
    let totals: MutableUsageTotals
    /// Sorted, so an entry re-encodes identically and an unchanged cache is
    /// recognised as unchanged.
    let ids: [String]

    init(_ file: DiscoveredFile, scan: FileScan, now: Date) {
        self.size = file.size
        self.modified = file.modified.timeIntervalSince1970
        // A later scan can only ask about windows starting at or after this one,
        // and a log's entries are no newer than its mtime, so samples older than
        // a week before both are dead weight.
        let horizon = LocalJSONLUsageProvider.weeklyCutoff(from: min(file.modified, now))
        self.totals = scan.isolated.pruningWindowSamples(before: horizon)
        self.ids = scan.ids.sorted()
    }

    /// True when the file is byte-for-byte the one this entry was parsed from,
    /// which is all replaying takes: the entry holds no window that could have
    /// gone stale, only totals and the timestamps the windows are derived from.
    func replays(_ file: DiscoveredFile) -> Bool {
        size == file.size && modified == file.modified.timeIntervalSince1970
    }
}

/// One counted entry's tokens with the time they were spent. Kept per entry
/// rather than pre-summed into the 5h/7d windows so a cached file can be
/// replayed against any later `now` and still land in the right windows.
private struct WindowSample: Codable, Equatable {
    let at: Double
    let tokens: Int
}

private struct MutableUsageTotals: Codable, Equatable {
    var input = 0
    var output = 0
    var reasoning = 0
    var cacheRead = 0
    var cacheWrite = 0
    var totalFallback = 0
    var sonnet = 0
    var samples = 0
    var windowSamples: [WindowSample] = []

    mutating func add(_ other: MutableUsageTotals) {
        input.clampedAdd(other.input)
        output.clampedAdd(other.output)
        reasoning.clampedAdd(other.reasoning)
        cacheRead.clampedAdd(other.cacheRead)
        cacheWrite.clampedAdd(other.cacheWrite)
        totalFallback.clampedAdd(other.totalFallback)
        sonnet.clampedAdd(other.sonnet)
        samples.clampedAdd(other.samples)
        windowSamples.append(contentsOf: other.windowSamples)
    }

    mutating func add(_ usage: ParsedUsage, timestamp: Date?, model: String?) {
        let total = usage.primary
        input.clampedAdd(usage.input)
        output.clampedAdd(usage.output)
        reasoning.clampedAdd(usage.reasoning)
        cacheRead.clampedAdd(usage.cacheRead)
        cacheWrite.clampedAdd(usage.cacheWrite)
        totalFallback.clampedAdd(usage.totalFallback)
        if let timestamp {
            windowSamples.append(WindowSample(at: timestamp.timeIntervalSince1970, tokens: total))
        }
        if model?.localizedCaseInsensitiveContains("sonnet") == true {
            sonnet.clampedAdd(total)
        }
        samples += 1
    }

    func tokens(since cutoff: Date) -> Int {
        let epoch = cutoff.timeIntervalSince1970
        var total = 0
        for sample in windowSamples where sample.at >= epoch {
            total.clampedAdd(sample.tokens)
        }
        return total
    }

    /// Drops samples no scan from `cutoff` on could still count, so a cached
    /// file carries only what its windows may still need.
    func pruningWindowSamples(before cutoff: Date) -> MutableUsageTotals {
        let epoch = cutoff.timeIntervalSince1970
        var pruned = self
        pruned.windowSamples = windowSamples.filter { $0.at >= epoch }
        return pruned
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
