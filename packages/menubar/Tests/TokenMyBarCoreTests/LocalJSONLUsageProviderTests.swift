import Foundation
import Testing
@testable import TokenMyBarCore

@Test func localJSONLScannerReadsClaudeShapeAndDedupesMessageID() throws {
    let root = try makeJSONLRoot(lines: [
        #"{"uuid":"u1","message":{"id":"m1","usage":{"input_tokens":10,"output_tokens":5,"cache_creation_input_tokens":20,"cache_read_input_tokens":3}}}"#,
        #"{"uuid":"u1","message":{"id":"m1","usage":{"input_tokens":10,"output_tokens":5,"cache_creation_input_tokens":20,"cache_read_input_tokens":3}}}"#,
    ])
    let provider = LocalJSONLUsageProvider(providerID: .claudeCode, roots: [root], authSummary: "test")

    let usage = try provider.scanUsage()

    #expect(usage.totalTokens == 38)
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
    for index in 0..<5 {
        let file = directory.appendingPathComponent("session-\(index).jsonl")
        let line = #"{"uuid":"u\#(index)","message":{"id":"m\#(index)","usage":{"input_tokens":10}}}"#
        try line.write(to: file, atomically: true, encoding: .utf8)
    }
    let provider = LocalJSONLUsageProvider(providerID: .codex, roots: [directory], authSummary: "test", maxFiles: 3)

    let usage = try provider.scanUsage()

    #expect(usage.sampleCount == 5)
    #expect(usage.weeklyTokens == 50)
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
