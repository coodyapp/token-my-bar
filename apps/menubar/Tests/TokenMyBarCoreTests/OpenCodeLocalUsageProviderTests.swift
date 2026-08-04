import CSQLite3
import Foundation
import Testing
@testable import TokenMyBarCore

@Test func openCodeLocalUsageReadsTokenTotals() throws {
    let databaseURL = try makeOpenCodeDatabase(rows: [
        (input: 100, output: 50, reasoning: 25, cacheRead: 10, cacheWrite: 5, secondsAgo: 0),
        (input: 200, output: 75, reasoning: 0, cacheRead: 20, cacheWrite: 10, secondsAgo: 0),
    ])

    let provider = OpenCodeLocalUsageProvider(databaseURL: databaseURL)
    let usage = try provider.readUsage()

    #expect(usage.tokensInput == 300)
    #expect(usage.tokensOutput == 125)
    #expect(usage.tokensReasoning == 25)
    #expect(usage.tokensCacheRead == 30)
    #expect(usage.tokensCacheWrite == 15)
    #expect(usage.totalTokens == 495)
    #expect(usage.sessionCount == 2)
}

@Test func openCodeSnapshotUsesMediumConfidenceWhenTokensExist() async throws {
    let databaseURL = try makeOpenCodeDatabase(rows: [
        (input: 100, output: 50, reasoning: 0, cacheRead: 0, cacheWrite: 0, secondsAgo: 0),
    ])

    let provider = OpenCodeLocalUsageProvider(databaseURL: databaseURL)
    let snapshot = await provider.snapshot()

    #expect(snapshot.providerID == .opencode)
    #expect(snapshot.status == .ok)
    #expect(snapshot.usedTokens == 150)
    #expect(snapshot.primarySource == .localFile)
    #expect(snapshot.confidence == .medium)
    #expect(snapshot.authSummary == "Local SQLite / no network auth")
    #expect(snapshot.usageRows.first?.title == "Session")
}

@Test func openCodeLocalUsageAppliesSessionAndWeeklyCutoffsIndependently() throws {
    let hour = 3_600.0
    let day = 24 * hour
    let databaseURL = try makeOpenCodeDatabase(rows: [
        // Inside both the 5h session window and the 7d weekly window.
        (input: 100, output: 0, reasoning: 0, cacheRead: 0, cacheWrite: 0, secondsAgo: 1 * hour),
        // Outside the session window, still inside the weekly window.
        (input: 200, output: 0, reasoning: 0, cacheRead: 0, cacheWrite: 0, secondsAgo: 6 * hour),
        // Outside both windows, but must still count toward the unconditional total.
        (input: 400, output: 0, reasoning: 0, cacheRead: 0, cacheWrite: 0, secondsAgo: 8 * day),
    ])

    let provider = OpenCodeLocalUsageProvider(databaseURL: databaseURL)
    let usage = try provider.readUsage()

    #expect(usage.sessionTokens == 100)
    #expect(usage.weeklyTokens == 300)
    #expect(usage.tokensInput == 700)
}

@Test func openCodeSnapshotStaysOkWhenOnlyWeeklyDataExists() async throws {
    // No usage in the last 5h but plenty this week is an ordinary morning;
    // a "No data" badge beside real weekly numbers is a contradiction.
    let databaseURL = try makeOpenCodeDatabase(rows: [
        (input: 100, output: 50, reasoning: 0, cacheRead: 0, cacheWrite: 0, secondsAgo: 6 * 3_600),
    ])

    let provider = OpenCodeLocalUsageProvider(databaseURL: databaseURL)
    let snapshot = await provider.snapshot()

    #expect(snapshot.status == .ok)
    #expect(snapshot.message == "No usage in the current 5h session")
    #expect(snapshot.usedTokens == nil)
    #expect(snapshot.usageRows.contains { $0.title == "Weekly" && $0.percent == nil })
}

@Test func openCodeSnapshotReportsMissingDatabase() async {
    let provider = OpenCodeLocalUsageProvider(
        databaseURL: URL(fileURLWithPath: "/tmp/token-my-bar-missing-opencode.db")
    )

    let snapshot = await provider.snapshot()

    #expect(snapshot.status == .noData)
    #expect(snapshot.usedTokens == nil)
}

private func makeOpenCodeDatabase(
    rows: [(input: Int, output: Int, reasoning: Int, cacheRead: Int, cacheWrite: Int, secondsAgo: Double)]
) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("opencode.db")

    var db: OpaquePointer?
    guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else {
        throw TestDatabaseError.openFailed
    }
    defer { sqlite3_close(db) }

    try execute(
        db,
        """
        CREATE TABLE session (
            id text PRIMARY KEY,
            tokens_input integer DEFAULT 0 NOT NULL,
            tokens_output integer DEFAULT 0 NOT NULL,
            tokens_reasoning integer DEFAULT 0 NOT NULL,
            tokens_cache_read integer DEFAULT 0 NOT NULL,
            tokens_cache_write integer DEFAULT 0 NOT NULL,
            time_updated integer NOT NULL
        );
        """
    )

    for (index, row) in rows.enumerated() {
        try execute(
            db,
            """
            INSERT INTO session (
                id,
                tokens_input,
                tokens_output,
                tokens_reasoning,
                tokens_cache_read,
                tokens_cache_write,
                time_updated
            ) VALUES (
                'session-\(index)',
                \(row.input),
                \(row.output),
                \(row.reasoning),
                \(row.cacheRead),
                \(row.cacheWrite),
                \(Int64((Date().timeIntervalSince1970 - row.secondsAgo) * 1000))
            );
            """
        )
    }

    return url
}

private func execute(_ db: OpaquePointer, _ sql: String) throws {
    var error: UnsafeMutablePointer<CChar>?
    guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
        let message = error.map { String(cString: $0) } ?? "Unknown SQLite error"
        sqlite3_free(error)
        throw TestDatabaseError.execFailed(message)
    }
}

private enum TestDatabaseError: Error {
    case openFailed
    case execFailed(String)
}

@Test func openCodeReportsSpendRecordedByOpenCodeItself() throws {
    // The `cost` column is OpenCode's own arithmetic; taking it means no model
    // price table to maintain and no divergence from what OpenCode reports.
    let usage = OpenCodeLocalUsage(
        tokensInput: 10, tokensOutput: 5, tokensReasoning: 0,
        tokensCacheRead: 0, tokensCacheWrite: 0,
        sessionTokens: 15, weeklyTokens: 15, sessionCount: 1,
        costUSD: 21.3968, lastUpdatedAt: nil
    )

    let spend = usage.rows.first { $0.key == "spend" }

    #expect(spend?.value == "$21.40")
    #expect(spend?.unit == .cost)
}

@Test func openCodeStillReadsADatabaseWithoutTheCostColumn() throws {
    // `cost` arrived in a later schema; asking for it unconditionally would fail
    // the whole query and lose every figure, not just the spend.
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let db = directory.appendingPathComponent("opencode.db")

    var handle: OpaquePointer?
    #expect(sqlite3_open(db.path, &handle) == SQLITE_OK)
    let legacy = """
    CREATE TABLE session (id TEXT, tokens_input INTEGER, tokens_output INTEGER,
      tokens_reasoning INTEGER, tokens_cache_read INTEGER, tokens_cache_write INTEGER,
      time_created INTEGER, time_updated INTEGER);
    INSERT INTO session VALUES ('s1', 10, 5, 0, 0, 0, 1, 1);
    """
    #expect(sqlite3_exec(handle, legacy, nil, nil, nil) == SQLITE_OK)
    sqlite3_close(handle)

    let usage = try OpenCodeLocalUsageProvider(databaseURL: db).readUsage()

    #expect(usage.tokensInput == 10)
    #expect(usage.costUSD == 0)
}

@Test func openCodeTotalsSaturateInsteadOfTrapping() {
    // Matches the JSONL provider's defensive arithmetic: a corrupt database
    // whose per-column sums individually fit Int64 must not trap the app on +.
    let usage = OpenCodeLocalUsage(
        tokensInput: .max,
        tokensOutput: .max,
        tokensReasoning: .max,
        tokensCacheRead: .max,
        tokensCacheWrite: .max,
        sessionTokens: 0,
        weeklyTokens: 0,
        sessionCount: 1,
        costUSD: 0,
        lastUpdatedAt: nil
    )
    #expect(usage.totalTokens == Int.max)
    #expect(usage.rows.allSatisfy { !$0.value.isEmpty })
}
