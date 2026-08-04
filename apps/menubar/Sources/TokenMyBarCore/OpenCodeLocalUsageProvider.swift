import CSQLite3
import Foundation

public enum OpenCodeLocalUsageError: Error, Equatable, Sendable {
    case databaseMissing(String)
    case openFailed(String)
    case queryFailed(String)
    case readFailed(String)
}

public struct OpenCodeLocalUsage: Equatable, Sendable {
    public let tokensInput: Int
    public let tokensOutput: Int
    public let tokensReasoning: Int
    public let tokensCacheRead: Int
    public let tokensCacheWrite: Int
    public let sessionTokens: Int
    public let weeklyTokens: Int
    public let sessionCount: Int
    /// What OpenCode itself recorded spending, in USD. Taken rather than
    /// computed: a price table per model would go stale every time a vendor
    /// changes one, and OpenCode already did the arithmetic.
    public let costUSD: Double
    public let lastUpdatedAt: Date?

    public var totalTokens: Int {
        tokensInput + tokensOutput + tokensReasoning + tokensCacheRead + tokensCacheWrite
    }

    public var primaryTokens: Int {
        sessionTokens
    }
}

public struct OpenCodeLocalUsageProvider: ProviderClient {
    public let providerID: ProviderID = .opencode
    private let databaseURL: URL?

    /// Leaving `databaseURL` nil resolves the default per read, so editing
    /// `[opencode] db` applies without relaunching the app.
    public init(databaseURL: URL? = nil) {
        self.databaseURL = databaseURL
    }

    /// Env wins over the config file: `TOKEN_MY_BAR_OPENCODE_DB` is scoped to
    /// the one invocation that exports it, while the file is permanent.
    /// `config` is loaded lazily rather than in a default argument: the
    /// environment override usually wins, and a default argument would still read
    /// the file from disk on every call to decide that.
    public static func defaultDatabaseURL(config: @autoclosure () -> AppConfig = AppConfig.load()) -> URL {
        if let override = ProcessInfo.processInfo.environment["TOKEN_MY_BAR_OPENCODE_DB"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        let config = config()
        // A hand-written path may still carry a `~` that no shell expanded.
        if let path = config.openCodeDatabasePath {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }

        let xdgDataHome = ProcessInfo.processInfo.environment["XDG_DATA_HOME"]
        let base = if let xdgDataHome, !xdgDataHome.isEmpty {
            URL(fileURLWithPath: xdgDataHome, isDirectory: true)
        } else {
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/share", isDirectory: true)
        }

        return base
            .appendingPathComponent("opencode", isDirectory: true)
            .appendingPathComponent("opencode.db")
    }

    public func snapshot() async -> ProviderSnapshot {
        do {
            // Synchronous SQLite work stays off the cooperative pool.
            let usage = try await BlockingIO.run { try readUsage() }
            return ProviderSnapshot(
                providerID: .opencode,
                // Any meaningful row makes the snapshot .ok: weekly numbers
                // under a "No data" badge read as a contradiction.
                status: usage.totalTokens > 0 ? .ok : .noData,
                usedTokens: usage.primaryTokens > 0 ? usage.primaryTokens : nil,
                unit: .tokens,
                windowName: .session,
                refreshedAt: Date(),
                primarySource: .localFile,
                sources: [.localFile],
                confidence: usage.primaryTokens > 0 ? .medium : .low,
                isEstimated: true,
                message: usage.primaryTokens > 0
                    ? "Local OpenCode sessions: \(usage.sessionCount)"
                    : (usage.totalTokens > 0
                        ? "No usage in the current 5h session"
                        : "OpenCode database found, but no token usage yet"),
                authSummary: "Local SQLite / no network auth",
                // Rows of zeros would read as real data downstream and displace
                // good cached numbers, so an empty database reports nothing.
                usageRows: usage.totalTokens > 0 ? usage.rows : []
            )
        } catch OpenCodeLocalUsageError.databaseMissing {
            return ProviderSnapshot(
                providerID: .opencode,
                status: .noData,
                usedTokens: nil,
                primarySource: .localFile,
                confidence: .low,
                isEstimated: true,
                message: "OpenCode local database not found",
                authSummary: "Run OpenCode once to create local database"
            )
        } catch {
            return ProviderSnapshot(
                providerID: .opencode,
                status: .error,
                usedTokens: nil,
                primarySource: .localFile,
                confidence: .low,
                isEstimated: true,
                message: "OpenCode local read failed: \(error.localizedDescription)",
                authSummary: "Local SQLite read failed"
            )
        }
    }


    static func columnExists(_ column: String, inTable table: String, db: OpaquePointer) -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table));", -1, &statement, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = sqlite3_column_text(statement, 1), String(cString: name) == column { return true }
        }
        return false
    }

    public func readUsage() throws -> OpenCodeLocalUsage {
        let databaseURL = self.databaseURL ?? Self.defaultDatabaseURL()
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw OpenCodeLocalUsageError.databaseMissing(databaseURL.path)
        }

        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(databaseURL.path, &db, flags, nil) == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite open error"
            if let db { sqlite3_close(db) }
            throw OpenCodeLocalUsageError.openFailed(message)
        }
        defer { sqlite3_close(db) }

        // `cost` arrived in a later OpenCode schema. Asking for it
        // unconditionally would fail the whole query on an older database and
        // lose every figure, not just the spend.
        let hasCost = Self.columnExists("cost", inTable: "session", db: db)

        let nowMS = Int64(Date().timeIntervalSince1970 * 1000)
        let sessionCutoffMS = nowMS - Int64(5 * 60 * 60 * 1000)
        let weeklyCutoffMS = nowMS - Int64(7 * 24 * 60 * 60 * 1000)

        // Windowed figures come from `message`, not `session`. A session row
        // holds lifetime totals, so gating it on time_updated attributed a whole
        // session's history to whichever window it was last touched in — a
        // backtest over 28 days of this database found 39% of five-hour readings
        // overstated, by 4.8x on average and 171x at worst. Per-message tokens
        // carry their own completion time and reconcile with the session rollup
        // exactly, so the window can simply be measured.
        let windowed = Self.columnExists("data", inTable: "message", db: db)
        let query = windowed ? """
        SELECT
          (SELECT COALESCE(SUM(tokens_input), 0) FROM session),
          (SELECT COALESCE(SUM(tokens_output), 0) FROM session),
          (SELECT COALESCE(SUM(tokens_reasoning), 0) FROM session),
          (SELECT COALESCE(SUM(tokens_cache_read), 0) FROM session),
          (SELECT COALESCE(SUM(tokens_cache_write), 0) FROM session),
          (SELECT COUNT(*) FROM session),
          (SELECT COALESCE(MAX(time_updated), 0) FROM session),
          w.win5h,
          w.win7d,
          \(hasCost ? "(SELECT COALESCE(SUM(cost), 0) FROM session)" : "0")
        FROM (
          SELECT
            COALESCE(SUM(CASE WHEN time_updated >= ? THEN tin + tout + trea END), 0) AS win5h,
            COALESCE(SUM(tin + tout + trea), 0) AS win7d
          FROM (
            SELECT time_updated,
              COALESCE(json_extract(data, '$.tokens.input'), 0) AS tin,
              COALESCE(json_extract(data, '$.tokens.output'), 0) AS tout,
              COALESCE(json_extract(data, '$.tokens.reasoning'), 0) AS trea
            FROM message WHERE time_updated >= ?
          )
        ) w;
        """ : """
        SELECT
          COALESCE(SUM(tokens_input), 0),
          COALESCE(SUM(tokens_output), 0),
          COALESCE(SUM(tokens_reasoning), 0),
          COALESCE(SUM(tokens_cache_read), 0),
          COALESCE(SUM(tokens_cache_write), 0),
          COUNT(*),
          MAX(time_updated),
          COALESCE(SUM(CASE WHEN time_updated >= ? THEN tokens_input + tokens_output + tokens_reasoning ELSE 0 END), 0),
          COALESCE(SUM(CASE WHEN time_updated >= ? THEN tokens_input + tokens_output + tokens_reasoning ELSE 0 END), 0),
          \(hasCost ? "COALESCE(SUM(cost), 0)" : "0")
        FROM session;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw OpenCodeLocalUsageError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, sessionCutoffMS)
        sqlite3_bind_int64(statement, 2, weeklyCutoffMS)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw OpenCodeLocalUsageError.readFailed(String(cString: sqlite3_errmsg(db)))
        }

        let lastUpdatedRaw = sqlite3_column_int64(statement, 6)
        return OpenCodeLocalUsage(
            tokensInput: Int(sqlite3_column_int64(statement, 0)),
            tokensOutput: Int(sqlite3_column_int64(statement, 1)),
            tokensReasoning: Int(sqlite3_column_int64(statement, 2)),
            tokensCacheRead: Int(sqlite3_column_int64(statement, 3)),
            tokensCacheWrite: Int(sqlite3_column_int64(statement, 4)),
            sessionTokens: Int(sqlite3_column_int64(statement, 7)),
            weeklyTokens: Int(sqlite3_column_int64(statement, 8)),
            sessionCount: Int(sqlite3_column_int64(statement, 5)),
            costUSD: sqlite3_column_double(statement, 9),
            lastUpdatedAt: lastUpdatedRaw > 0 ? Date(timeIntervalSince1970: TimeInterval(lastUpdatedRaw / 1000)) : nil
        )
    }
}

extension OpenCodeLocalUsage {
    var rows: [UsageRow] {
        [
            UsageRow(
                key: "session",
                title: "Session",
                subtitle: "Last 5h local tokens",
                value: Format.count(sessionTokens),
                percent: nil,
                trend: .unknown,
                unit: .tokens
            ),
            UsageRow(
                key: "weekly",
                title: "Weekly",
                subtitle: "Last 7d local tokens",
                value: Format.count(weeklyTokens),
                percent: nil,
                trend: .unknown,
                unit: .tokens
            ),
            UsageRow(
                key: "spend",
                title: "Billed API spend",
                subtitle: "All time, excludes subscription models",
                value: Format.money(costUSD),
                iconName: "dollarsign.circle",
                percent: nil,
                trend: .unknown,
                unit: .cost
            ),
            UsageRow(
                key: "cache-reasoning",
                title: "Cache + reasoning",
                subtitle: "All time, not windowed like Session/Weekly",
                value: Format.count(tokensCacheRead + tokensCacheWrite + tokensReasoning),
                percent: nil,
                trend: .unknown,
                unit: .tokens
            ),
        ]
    }
}
