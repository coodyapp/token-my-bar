import CSQLite3
import Foundation
import Testing
@testable import TokenMyBarCore

@Test func openCodeLocalUsageReadsTokenTotals() throws {
    let databaseURL = try makeOpenCodeDatabase(rows: [
        (input: 100, output: 50, reasoning: 25, cacheRead: 10, cacheWrite: 5),
        (input: 200, output: 75, reasoning: 0, cacheRead: 20, cacheWrite: 10),
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
        (input: 100, output: 50, reasoning: 0, cacheRead: 0, cacheWrite: 0),
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

@Test func openCodeSnapshotReportsMissingDatabase() async {
    let provider = OpenCodeLocalUsageProvider(
        databaseURL: URL(fileURLWithPath: "/tmp/token-my-bar-missing-opencode.db")
    )

    let snapshot = await provider.snapshot()

    #expect(snapshot.status == .noData)
    #expect(snapshot.usedTokens == nil)
}

private func makeOpenCodeDatabase(
    rows: [(input: Int, output: Int, reasoning: Int, cacheRead: Int, cacheWrite: Int)]
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
                \(Int64(Date().timeIntervalSince1970 * 1000))
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
