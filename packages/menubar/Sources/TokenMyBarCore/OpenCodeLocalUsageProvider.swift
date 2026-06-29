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
    private let databaseURL: URL

    public init(databaseURL: URL = OpenCodeLocalUsageProvider.defaultDatabaseURL()) {
        self.databaseURL = databaseURL
    }

    public static func defaultDatabaseURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["TOKEN_MY_BAR_OPENCODE_DB"], !override.isEmpty {
            return URL(fileURLWithPath: override)
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
            let usage = try readUsage()
            return ProviderSnapshot(
                providerID: .opencode,
                status: usage.primaryTokens > 0 ? .ok : .noData,
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
                    : "OpenCode database found, but no token usage yet",
                authSummary: "Local SQLite / no network auth",
                usageRows: usage.rows
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

    public func readUsage() throws -> OpenCodeLocalUsage {
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

        let nowMS = Int64(Date().timeIntervalSince1970 * 1000)
        let sessionCutoffMS = nowMS - Int64(5 * 60 * 60 * 1000)
        let weeklyCutoffMS = nowMS - Int64(7 * 24 * 60 * 60 * 1000)

        let query = """
        SELECT
          COALESCE(SUM(tokens_input), 0),
          COALESCE(SUM(tokens_output), 0),
          COALESCE(SUM(tokens_reasoning), 0),
          COALESCE(SUM(tokens_cache_read), 0),
          COALESCE(SUM(tokens_cache_write), 0),
          COUNT(*),
          MAX(time_updated),
          COALESCE(SUM(CASE WHEN time_updated >= ? THEN tokens_input + tokens_output + tokens_reasoning ELSE 0 END), 0),
          COALESCE(SUM(CASE WHEN time_updated >= ? THEN tokens_input + tokens_output + tokens_reasoning ELSE 0 END), 0)
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
                value: Self.formatCount(sessionTokens),
                percent: nil,
                trend: .unknown,
                unit: .tokens
            ),
            UsageRow(
                key: "weekly",
                title: "Weekly",
                subtitle: "Last 7d local tokens",
                value: Self.formatCount(weeklyTokens),
                percent: nil,
                trend: .unknown,
                unit: .tokens
            ),
            UsageRow(
                key: "cache-reasoning",
                title: "Cache + reasoning",
                subtitle: "Local cache/reasoning tokens",
                value: Self.formatCount(tokensCacheRead + tokensCacheWrite + tokensReasoning),
                percent: nil,
                trend: .unknown,
                unit: .tokens
            ),
        ]
    }

    private static func formatCount(_ value: Int) -> String {
        if value >= 1_000_000 {
            return "\(value / 1_000_000)M"
        }
        if value >= 1_000 {
            return "\(value / 1_000)K"
        }
        return "\(value)"
    }
}
