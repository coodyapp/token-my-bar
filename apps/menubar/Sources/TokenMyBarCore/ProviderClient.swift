import Foundation

public protocol ProviderClient: Sendable {
    var providerID: ProviderID { get }
    func snapshot() async -> ProviderSnapshot
}

public struct ProviderRegistry: Sendable {
    public let providers: [any ProviderClient]

    public init(providers: [any ProviderClient] = ProviderRegistry.defaultProviders()) {
        self.providers = providers
    }

    public static func defaultProviders() -> [any ProviderClient] {
        [
            FallbackProvider(primary: OpenCodeCookieUsageProvider(), fallback: OpenCodeLocalUsageProvider()),
            FallbackProvider(primary: CodexOAuthUsageProvider(), fallback: LocalJSONLUsageProvider.codex()),
            FallbackProvider(primary: ClaudeOAuthUsageProvider(), fallback: LocalJSONLUsageProvider.claude()),
        ]
    }
}

public struct FallbackProvider<Primary: ProviderClient, Fallback: ProviderClient>: ProviderClient {
    public let providerID: ProviderID
    private let primary: Primary
    private let fallback: Fallback

    public init(primary: Primary, fallback: Fallback) {
        self.providerID = primary.providerID
        self.primary = primary
        self.fallback = fallback
    }

    public func snapshot() async -> ProviderSnapshot {
        let official = await primary.snapshot()
        if official.status == .ok { return official }

        let local = await fallback.snapshot()
        guard local.status == .ok || !local.usageRows.isEmpty else { return official }
        // Intentional: unauthenticated wins over local.status so StatusBadge keeps signaling "go re-auth" instead of masking it as merely stale data.
        return ProviderSnapshot(
            providerID: providerID,
            status: official.status == .unauthenticated ? .unauthenticated : local.status,
            usedTokens: local.usedTokens ?? official.usedTokens,
            limitTokens: official.limitTokens,
            unit: official.unit,
            usagePercent: local.usagePercent ?? official.usagePercent,
            windowName: official.windowName,
            resetAt: official.resetAt,
            refreshedAt: Date(),
            primarySource: local.primarySource,
            sources: Array(Set(official.sources + local.sources)).sorted { $0.rawValue < $1.rawValue },
            confidence: local.confidence,
            isEstimated: true,
            message: official.message ?? local.message,
            authSummary: "Official source unavailable; showing local history",
            planName: official.planName ?? local.planName,
            usageRows: local.usageRows
        )
    }
}
