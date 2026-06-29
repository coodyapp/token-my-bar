import Foundation

public enum ProviderID: String, CaseIterable, Codable, Sendable {
    case codex
    case claudeCode = "claude-code"
    case opencode

    public var displayName: String {
        switch self {
        case .codex:
            "OpenAI Codex"
        case .claudeCode:
            "Claude Code"
        case .opencode:
            "OpenCode"
        }
    }
}

public enum ProviderStatus: String, Codable, Sendable {
    case ok
    case loading
    case stale
    case noData = "no-data"
    case unauthenticated
    case error
}

public enum UsageUnit: String, Codable, Sendable {
    case tokens
    case credits
    case cost
    case requests
    case unknown
}

public enum UsageWindow: String, Codable, Sendable {
    case session
    case daily
    case weekly
    case monthly
    case billing
    case unknown
}

public enum UsageSource: String, Codable, Sendable {
    case localFile = "local-file"
    case keychain
    case localLog = "local-log"
    case api
    case oauth
    case browserCookie = "browser-cookie"
}

public enum SnapshotConfidence: String, Codable, Sendable {
    case high
    case medium
    case low
}

public enum UsageTrend: String, Codable, Sendable {
    case up
    case down
    case flat
    case unknown
}

/// Severity bucket used by the UI to pick a native color for a usage bar.
public enum UsageSeverity: String, Codable, Sendable {
    case normal
    case warning
    case critical

    public init(percent: Double?) {
        guard let percent else { self = .normal; return }
        switch percent {
        case ..<70: self = .normal
        case ..<90: self = .warning
        default: self = .critical
        }
    }
}

public struct UsageRow: Codable, Equatable, Sendable, Identifiable {
    public var id: String { key }

    public let key: String
    public let title: String
    public let subtitle: String?
    public let value: String
    /// Optional trailing text rendered on the right of the usage line (e.g. reset countdown).
    public let detail: String?
    /// SF Symbol name to show next to the row title.
    public let iconName: String?
    public let percent: Double?
    public let trend: UsageTrend
    public let unit: UsageUnit

    public init(
        key: String,
        title: String,
        subtitle: String? = nil,
        value: String,
        detail: String? = nil,
        iconName: String? = nil,
        percent: Double? = nil,
        trend: UsageTrend = .unknown,
        unit: UsageUnit = .unknown
    ) {
        self.key = key
        self.title = title
        self.subtitle = subtitle
        self.value = value
        self.detail = detail
        self.iconName = iconName
        self.percent = percent
        self.trend = trend
        self.unit = unit
    }
}

public struct ProviderSnapshot: Codable, Equatable, Sendable, Identifiable {
    public var id: ProviderID { providerID }

    public let providerID: ProviderID
    public let displayName: String
    public let status: ProviderStatus
    public let usedTokens: Int?
    public let limitTokens: Int?
    public let unit: UsageUnit
    public let usagePercent: Double?
    public let windowName: UsageWindow
    public let resetAt: Date?
    public let refreshedAt: Date
    public let primarySource: UsageSource
    public let sources: [UsageSource]
    public let confidence: SnapshotConfidence
    public let isEstimated: Bool
    public let message: String?
    public let authSummary: String?
    /// Plan/tier label shown in the popover header (e.g. "Max", "Pro").
    public let planName: String?
    public let usageRows: [UsageRow]

    public init(
        providerID: ProviderID,
        displayName: String? = nil,
        status: ProviderStatus,
        usedTokens: Int?,
        limitTokens: Int? = nil,
        unit: UsageUnit = .tokens,
        usagePercent: Double? = nil,
        windowName: UsageWindow = .unknown,
        resetAt: Date? = nil,
        refreshedAt: Date = Date(),
        primarySource: UsageSource,
        sources: [UsageSource]? = nil,
        confidence: SnapshotConfidence,
        isEstimated: Bool,
        message: String? = nil,
        authSummary: String? = nil,
        planName: String? = nil,
        usageRows: [UsageRow] = []
    ) {
        self.providerID = providerID
        self.displayName = displayName ?? providerID.displayName
        self.status = status
        self.usedTokens = usedTokens
        self.limitTokens = limitTokens
        self.unit = unit
        self.usagePercent = usagePercent
        self.windowName = windowName
        self.resetAt = resetAt
        self.refreshedAt = refreshedAt
        self.primarySource = primarySource
        self.sources = sources ?? [primarySource]
        self.confidence = confidence
        self.isEstimated = isEstimated
        self.message = message
        self.authSummary = authSummary
        self.planName = planName
        self.usageRows = usageRows
    }

    public func staleCopy(message: String? = nil, refreshedAt: Date = Date()) -> ProviderSnapshot {
        ProviderSnapshot(
            providerID: providerID,
            displayName: displayName,
            status: .stale,
            usedTokens: usedTokens,
            limitTokens: limitTokens,
            unit: unit,
            usagePercent: usagePercent,
            windowName: windowName,
            resetAt: resetAt,
            refreshedAt: refreshedAt,
            primarySource: primarySource,
            sources: sources,
            confidence: confidence,
            isEstimated: isEstimated,
            message: message ?? self.message,
            authSummary: authSummary,
            planName: planName,
            usageRows: usageRows
        )
    }
}
