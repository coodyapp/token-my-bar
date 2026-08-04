import Foundation
import Testing
@testable import TokenMyBarCore

@Test func localJSONLScannerReadsClaudeShapeAndDedupesMessageID() throws {
    // Claude Code writes one record per assistant content block: the top-level
    // uuid differs per line while message.id and the cumulative usage repeat.
    // Deduping on the per-line uuid would count the same usage 2-3x.
    let root = try makeJSONLRoot(lines: [
        #"{"uuid":"u1","message":{"id":"m1","usage":{"input_tokens":10,"output_tokens":5,"cache_creation_input_tokens":20,"cache_read_input_tokens":3}}}"#,
        #"{"uuid":"u2","message":{"id":"m1","usage":{"input_tokens":10,"output_tokens":5,"cache_creation_input_tokens":20,"cache_read_input_tokens":3}}}"#,
    ])
    let provider = LocalJSONLUsageProvider(providerID: .claudeCode, roots: [root], authSummary: "test")

    let usage = try provider.scanUsage()

    #expect(usage.totalTokens == 38)
    #expect(usage.sampleCount == 1)
}

@Test func localJSONLScannerCountsDistinctMessagesSeparately() throws {
    let root = try makeJSONLRoot(lines: [
        #"{"uuid":"u1","message":{"id":"m1","usage":{"input_tokens":10}}}"#,
        #"{"uuid":"u2","message":{"id":"m2","usage":{"input_tokens":10}}}"#,
    ])
    let provider = LocalJSONLUsageProvider(providerID: .claudeCode, roots: [root], authSummary: "test")

    let usage = try provider.scanUsage()

    #expect(usage.totalTokens == 20)
    #expect(usage.sampleCount == 2)
}

@Test func localJSONLScannerClampsOutOfRangeTokenCountsInsteadOfTrapping() throws {
    // Third-party tools also write into the scanned directories; a single line
    // carrying a number beyond Int.max used to trap `Int(Double)` and crash the
    // app on every launch, since the file is re-read on each refresh.
    let root = try makeJSONLRoot(lines: [
        #"{"id":"m1","usage":{"input_tokens":1e300,"output_tokens":-5,"total_tokens":99999999999999999999}}"#,
        #"{"id":"m2","usage":{"input_tokens":7}}"#,
    ])
    let provider = LocalJSONLUsageProvider(providerID: .codex, roots: [root], authSummary: "test")

    let usage = try provider.scanUsage()

    #expect(usage.inputTokens == LocalJSONLUsageProvider.maxTokenValue + 7)
    #expect(usage.outputTokens == 0)
    #expect(usage.totalTokens > 0)
}

@Test func localJSONLScannerSkipsUnreadableFilesInsteadOfAbortingScan() throws {
    let directory = try makeJSONLDirectory()
    let readable = directory.appendingPathComponent("readable.jsonl")
    try #"{"id":"m1","usage":{"input_tokens":10}}"#.write(to: readable, atomically: true, encoding: .utf8)
    let unreadable = directory.appendingPathComponent("unreadable.jsonl")
    try #"{"id":"m2","usage":{"input_tokens":10}}"#.write(to: unreadable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: unreadable.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: unreadable.path) }

    let provider = LocalJSONLUsageProvider(providerID: .codex, roots: [directory], authSummary: "test")
    let usage = try provider.scanUsage()

    #expect(usage.inputTokens == 10)
    #expect(usage.sampleCount == 1)
}

@Test func localJSONLScannerReadsCodexShape() throws {
    let root = try makeJSONLRoot(lines: [
        #"{"id":"msg1","usage":{"prompt_tokens":100,"completion_tokens":50,"reasoning_tokens":25}}"#,
        #"{"id":"msg2","usage":{"total_tokens":9}}"#,
    ])
    let provider = LocalJSONLUsageProvider(providerID: .codex, roots: [root], authSummary: "test")

    let usage = try provider.scanUsage()

    #expect(usage.inputTokens == 100)
    #expect(usage.outputTokens == 50)
    #expect(usage.reasoningTokens == 25)
    #expect(usage.totalTokens == 184)
    #expect(usage.sampleCount == 2)
}

@Test func localJSONLScannerNeverTruncatesFilesWithinWeeklyWindow() throws {
    let directory = try makeJSONLDirectory()
    // All five files are recent (default mtime = now), so they all fall
    // inside the 7-day weekly window. A cap of 3 must not drop any of them —
    // only files older than the weekly window may be capped.
    let timestamp = ISO8601DateFormatter().string(from: Date())
    for index in 0..<5 {
        let file = directory.appendingPathComponent("session-\(index).jsonl")
        let line = #"{"uuid":"u\#(index)","timestamp":"\#(timestamp)","message":{"id":"m\#(index)","usage":{"input_tokens":10}}}"#
        try line.write(to: file, atomically: true, encoding: .utf8)
    }
    let provider = LocalJSONLUsageProvider(providerID: .codex, roots: [directory], authSummary: "test", maxFiles: 3)

    let usage = try provider.scanUsage()

    #expect(usage.sampleCount == 5)
    #expect(usage.weeklyTokens == 50)
}

@Test func localJSONLScannerExcludesTimestamplessRecordsFromWindowedTotals() throws {
    let root = try makeJSONLRoot(lines: [
        #"{"uuid":"u1","message":{"id":"m1","usage":{"input_tokens":10}}}"#,
    ])
    let provider = LocalJSONLUsageProvider(providerID: .codex, roots: [root], authSummary: "test")

    let usage = try provider.scanUsage()

    #expect(usage.inputTokens == 10)
    #expect(usage.sessionTokens == 0)
    #expect(usage.weeklyTokens == 0)
}

@Test func localJSONLScannerParsesFractionalSecondTimestampsIntoWindows() throws {
    // Real Claude Code logs write ISO8601 timestamps WITH fractional seconds
    // (e.g. 2026-07-04T03:10:20.906Z). A bare ISO8601DateFormatter rejects the
    // fractional form, so without fractional-aware parsing these recent entries
    // are silently dropped from the session/weekly totals.
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let timestamp = formatter.string(from: Date())
    let root = try makeJSONLRoot(lines: [
        #"{"uuid":"u1","timestamp":"\#(timestamp)","message":{"id":"m1","usage":{"input_tokens":10,"output_tokens":5}}}"#,
    ])
    let provider = LocalJSONLUsageProvider(providerID: .claudeCode, roots: [root], authSummary: "test")

    let usage = try provider.scanUsage()

    #expect(usage.sessionTokens == 15)
    #expect(usage.weeklyTokens == 15)
}

@Test func localJSONLSnapshotOmitsRowsWhenNothingWasFound() async throws {
    // Zero-valued rows read as real data to every consumer — the merger would
    // show "Session 0 / Weekly 0" in place of good cached numbers.
    let root = try makeJSONLRoot(lines: [
        #"{"id":"m1","usage":{"input_tokens":0,"output_tokens":0}}"#,
    ])
    let provider = LocalJSONLUsageProvider(providerID: .codex, roots: [root], authSummary: "test")

    let snapshot = await provider.snapshot()

    #expect(snapshot.status == .noData)
    #expect(snapshot.usageRows.isEmpty)
}

@Test func localJSONLSnapshotKeepsRowsWhenOnlyTheSessionWindowIsEmpty() async throws {
    // No usage in the last 5h but plenty this week is an ordinary morning, and
    // those weekly numbers are exactly what the user opens the app for.
    let timestamp = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-24 * 60 * 60))
    let root = try makeJSONLRoot(lines: [
        #"{"id":"m1","timestamp":"\#(timestamp)","usage":{"input_tokens":10,"output_tokens":5}}"#,
    ])
    let provider = LocalJSONLUsageProvider(providerID: .codex, roots: [root], authSummary: "test")

    let snapshot = await provider.snapshot()

    // Real weekly numbers under a "No data" badge is a contradiction: any
    // meaningful row makes the snapshot .ok, even with the 5h window empty.
    #expect(snapshot.status == .ok)
    #expect(snapshot.message == "No usage in the current 5h session")
    #expect(snapshot.usedTokens == nil)
    #expect(snapshot.usageRows.contains { $0.key == "weekly" && $0.value == "15" })
}

@Test func localJSONLRowsDoNotTrapOnSaturatedTotals() {
    // Clamping per value keeps corrupt logs from trapping the parse; the rows
    // that display those totals have to survive the same input.
    let saturated = Int.max / 3 + 1
    let usage = LocalJSONLUsage(
        inputTokens: 0,
        outputTokens: 0,
        reasoningTokens: saturated,
        cacheReadTokens: saturated,
        cacheWriteTokens: saturated,
        totalFallbackTokens: 0,
        sessionTokens: 0,
        weeklyTokens: 0,
        sonnetTokens: 0,
        sampleCount: 1,
        fileCount: 1,
        lastUpdatedAt: nil
    )

    let rows = usage.rows(for: .claudeCode)

    #expect(rows.contains { $0.key == "cache-reasoning" })
    #expect(usage.totalTokens == .max)
}

@Test func localJSONLSnapshotReportsMissingLogs() async {
    let provider = LocalJSONLUsageProvider(
        providerID: .codex,
        roots: [URL(fileURLWithPath: "/tmp/token-my-bar-missing-jsonl")],
        authSummary: "test"
    )

    let snapshot = await provider.snapshot()

    #expect(snapshot.status == .noData)
    #expect(snapshot.usedTokens == nil)
}

@Test func localJSONLScannerCountsFilesLargerThanTwentyMegabytes() throws {
    // A 20 MB per-file cap dropped a heavy user's busiest session file whole,
    // measured as a 25% undercount, while the chunked reader walks it fine.
    let directory = try makeJSONLDirectory()
    let file = directory.appendingPathComponent("huge.jsonl")
    let padding = String(repeating: "a", count: 128 * 1024)
    var lines = [#"{"message":{"id":"m1","usage":{"input_tokens":10}}}"#]
    lines += (0..<170).map { #"{"pad\#($0)":"\#(padding)"}"# }
    try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
    let size = try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int
    #expect(size ?? 0 > 20 * 1024 * 1024)

    let provider = LocalJSONLUsageProvider(providerID: .claudeCode, roots: [directory], authSummary: "test")
    let usage = try provider.scanUsage()

    #expect(usage.fileCount == 1)
    #expect(usage.inputTokens == 10)
}

@Test func localJSONLScannerReplaysUnchangedFilesFromCacheInsteadOfRereading() throws {
    let root = try makeJSONLRoot(lines: [
        #"{"uuid":"u1","message":{"id":"m1","usage":{"input_tokens":10}}}"#,
    ])
    let cacheURL = root.appendingPathComponent("cache/local-scan.json")
    let provider = LocalJSONLUsageProvider(
        providerID: .claudeCode,
        roots: [root],
        authSummary: "test",
        cacheURL: cacheURL
    )

    #expect(try provider.scanUsage().inputTokens == 10)

    // chmod leaves size and mtime untouched, so the cache key still matches
    // while the parse path cannot read a byte: 10 can now only come from the
    // cache, and the cacheless control proves the file really is unreadable.
    let file = root.appendingPathComponent("session.jsonl")
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path) }
    let control = LocalJSONLUsageProvider(providerID: .claudeCode, roots: [root], authSummary: "test")

    #expect(try provider.scanUsage().inputTokens == 10)
    #expect(try control.scanUsage().inputTokens == 0)
}

@Test func localJSONLScannerRecomputesWindowsForReplayedFiles() throws {
    // Session and weekly are relative to now, so a file cached an hour ago must
    // not replay the window totals it had then — it replays its timestamps and
    // the windows are summed again.
    let start = Date()
    let timestamp = ISO8601DateFormatter().string(from: start.addingTimeInterval(-60 * 60))
    let root = try makeJSONLRoot(lines: [
        #"{"timestamp":"\#(timestamp)","message":{"id":"m1","usage":{"input_tokens":10,"output_tokens":5}}}"#,
    ])
    let cacheURL = root.appendingPathComponent("cache/local-scan.json")
    let provider = LocalJSONLUsageProvider(
        providerID: .claudeCode,
        roots: [root],
        authSummary: "test",
        cacheURL: cacheURL
    )

    let fresh = try provider.scanUsage(now: start)
    #expect(fresh.sessionTokens == 15)
    #expect(fresh.weeklyTokens == 15)

    let file = root.appendingPathComponent("session.jsonl")
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path) }

    // Six hours on: out of the 5h session window, still inside the week.
    let replayed = try provider.scanUsage(now: start.addingTimeInterval(6 * 60 * 60))
    #expect(replayed.inputTokens == 10)
    #expect(replayed.sessionTokens == 0)
    #expect(replayed.weeklyTokens == 15)
}

@Test func localJSONLScannerRereadsFilesWhoseSizeOrMTimeChanged() throws {
    let root = try makeJSONLRoot(lines: [#"{"message":{"id":"m1","usage":{"input_tokens":10}}}"#])
    let cacheURL = root.appendingPathComponent("cache/local-scan.json")
    let file = root.appendingPathComponent("session.jsonl")
    let provider = LocalJSONLUsageProvider(
        providerID: .claudeCode,
        roots: [root],
        authSummary: "test",
        cacheURL: cacheURL
    )
    #expect(try provider.scanUsage().inputTokens == 10)

    // Same byte count, different mtime: an edit in place is caught by the mtime
    // half of the key alone.
    try #"{"message":{"id":"m1","usage":{"input_tokens":99}}}"#
        .write(to: file, atomically: true, encoding: .utf8)
    try setModificationDate(of: file, to: Date().addingTimeInterval(-60))
    #expect(try provider.scanUsage().inputTokens == 99)

    try [#"{"message":{"id":"m1","usage":{"input_tokens":99}}}"#,
         #"{"message":{"id":"m2","usage":{"input_tokens":1}}}"#]
        .joined(separator: "\n")
        .write(to: file, atomically: true, encoding: .utf8)
    #expect(try provider.scanUsage().inputTokens == 100)
}

@Test func localJSONLScannerDoesNotDoubleCountMessagesSharedAcrossFiles() throws {
    // Resuming a session replays earlier messages verbatim into a second log, so
    // one message.id legitimately lives in two files. Per-file cached totals
    // count it in both, so the cache has to defer to the cross-file dedupe.
    let directory = try makeJSONLDirectory()
    let cacheURL = directory.appendingPathComponent("cache/local-scan.json")
    let shared = #"{"message":{"id":"m1","usage":{"input_tokens":10}}}"#
    // mtimes pin the scan order, which decides which file's copy of m1 counts.
    try writeJSONL([shared, #"{"message":{"id":"m2","usage":{"input_tokens":5}}}"#],
                   to: directory.appendingPathComponent("resumed.jsonl"),
                   modified: Date().addingTimeInterval(-60))
    try writeJSONL([shared, #"{"message":{"id":"m3","usage":{"input_tokens":7}}}"#],
                   to: directory.appendingPathComponent("original.jsonl"),
                   modified: Date().addingTimeInterval(-120))
    let provider = LocalJSONLUsageProvider(
        providerID: .claudeCode,
        roots: [directory],
        authSummary: "test",
        cacheURL: cacheURL
    )
    let control = LocalJSONLUsageProvider(providerID: .claudeCode, roots: [directory], authSummary: "test")

    let cold = try provider.scanUsage()
    let warm = try provider.scanUsage()

    #expect(cold.inputTokens == 22)
    #expect(warm.inputTokens == 22)
    #expect(try control.scanUsage().inputTokens == 22)
}

@Test func localJSONLScannerFallsBackToFullScanOnCorruptCache() throws {
    let root = try makeJSONLRoot(lines: [#"{"message":{"id":"m1","usage":{"input_tokens":10}}}"#])
    let cacheURL = root.appendingPathComponent("cache/local-scan.json")
    try FileManager.default.createDirectory(
        at: cacheURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try Data("{ not json".utf8).write(to: cacheURL)
    let provider = LocalJSONLUsageProvider(
        providerID: .claudeCode,
        roots: [root],
        authSummary: "test",
        cacheURL: cacheURL
    )

    #expect(try provider.scanUsage().inputTokens == 10)
    // The unusable file is replaced by a usable one, and it holds a map of the
    // user's project paths, so it must not be world-readable.
    let permissions = try FileManager.default.attributesOfItem(atPath: cacheURL.path)[.posixPermissions] as? Int
    #expect(permissions == 0o600)
    #expect(try provider.scanUsage().inputTokens == 10)
}

@Test func localJSONLScanCacheLivesBesideTheSnapshotCache() {
    #expect(
        LocalJSONLUsageProvider.defaultCacheURL(for: .claudeCode).deletingLastPathComponent()
            == SnapshotStore.defaultURL().deletingLastPathComponent()
    )
    #expect(
        LocalJSONLUsageProvider.defaultCacheURL(for: .claudeCode)
            != LocalJSONLUsageProvider.defaultCacheURL(for: .codex)
    )
}

private func writeJSONL(_ lines: [String], to file: URL, modified: Date) throws {
    try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
    try setModificationDate(of: file, to: modified)
}

private func setModificationDate(of file: URL, to date: Date) throws {
    try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file.path)
}

private func makeJSONLRoot(lines: [String]) throws -> URL {
    let directory = try makeJSONLDirectory()
    let file = directory.appendingPathComponent("session.jsonl")
    try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
    return directory
}

private func makeJSONLDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}
