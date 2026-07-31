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

    /// SF Symbol used to represent this vendor in the menu bar and popover.
    /// Lives here so the UI derives it instead of duplicating a switch per view.
    public var iconName: String {
        switch self {
        case .codex:
            "terminal"
        case .claudeCode:
            "sparkles"
        case .opencode:
            "chevron.left.forwardslash.chevron.right"
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
    /// Optional trailing text rendered on the right of the usage line, for
    /// details that are not a countdown (e.g. "Starts when a message is sent").
    public let detail: String?
    /// SF Symbol name to show next to the row title.
    public let iconName: String?
    /// When this window rolls over. Stored as a date, not a rendered countdown:
    /// a cached row keeps whatever string it was built with, so "Resets in 26m"
    /// would still read that way weeks later.
    public let resetAt: Date?
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
        resetAt: Date? = nil,
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
        self.resetAt = resetAt
        self.percent = percent
        self.trend = trend
        self.unit = unit
    }

    /// Countdown for this window as of `now`, or `nil` once it has elapsed.
    public func resetText(now: Date = Date()) -> String? {
        guard let resetAt else { return nil }
        guard resetAt > now else { return nil }
        return Format.resetCountdown(until: resetAt, now: now)
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

    /// Cached data re-presented as the current view. `status` overrides the
    /// default so a state the user must act on (expired auth) is not flattened
    /// into "stale", which reads as merely out of date.
    ///
    /// `refreshedAt` defaults to the time this reading was actually taken:
    /// restamping it to now would tell the user — and every consumer of the
    /// `updated_at` field — that days-old numbers are current.
    public func staleCopy(
        status: ProviderStatus = .stale,
        message: String? = nil,
        refreshedAt: Date? = nil
    ) -> ProviderSnapshot {
        ProviderSnapshot(
            providerID: providerID,
            displayName: displayName,
            status: status,
            usedTokens: usedTokens,
            limitTokens: limitTokens,
            unit: unit,
            usagePercent: usagePercent,
            windowName: windowName,
            resetAt: resetAt,
            refreshedAt: refreshedAt ?? self.refreshedAt,
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
