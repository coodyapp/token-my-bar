import Foundation
import Testing
@testable import TokenMyBarCore

private struct StubProvider: ProviderClient {
    let providerID: ProviderID
    let result: ProviderSnapshot
    func snapshot() async -> ProviderSnapshot { result }
}

private func snapshot(
    _ id: ProviderID,
    status: ProviderStatus,
    percent: Double? = nil,
    used: Int? = nil,
    source: UsageSource = .oauth,
    rows: [UsageRow] = []
) -> ProviderSnapshot {
    ProviderSnapshot(
        providerID: id,
        status: status,
        usedTokens: used,
        usagePercent: percent,
        primarySource: source,
        sources: [source],
        confidence: .high,
        isEstimated: false,
        usageRows: rows
    )
}

@Test func fallbackReturnsOfficialWhenOK() async {
    let official = snapshot(.codex, status: .ok, percent: 50)
    let local = snapshot(.codex, status: .ok, used: 999, source: .localLog)
    let provider = FallbackProvider(
        primary: StubProvider(providerID: .codex, result: official),
        fallback: StubProvider(providerID: .codex, result: local)
    )

    let result = await provider.snapshot()
    #expect(result.status == .ok)
    #expect(result.usagePercent == 50)
    #expect(result.primarySource == .oauth)
}

@Test func fallbackKeepsUnauthenticatedButShowsLocalRows() async {
    let official = snapshot(.claudeCode, status: .unauthenticated)
    let rows = [UsageRow(key: "session", title: "Session", value: "12K")]
    let local = snapshot(.claudeCode, status: .ok, used: 12_000, source: .localLog, rows: rows)
    let provider = FallbackProvider(
        primary: StubProvider(providerID: .claudeCode, result: official),
        fallback: StubProvider(providerID: .claudeCode, result: local)
    )

    let result = await provider.snapshot()
    #expect(result.status == .unauthenticated)
    #expect(result.usageRows == rows)
    #expect(result.usedTokens == 12_000)
    #expect(result.isEstimated)
}

@Test func fallbackUsesLocalStatusOnError() async {
    let official = snapshot(.opencode, status: .error)
    let rows = [UsageRow(key: "rolling", title: "Rolling", value: "1K")]
    let local = snapshot(.opencode, status: .ok, used: 1_000, source: .localFile, rows: rows)
    let provider = FallbackProvider(
        primary: StubProvider(providerID: .opencode, result: official),
        fallback: StubProvider(providerID: .opencode, result: local)
    )

    let result = await provider.snapshot()
    #expect(result.status == .ok)
    #expect(result.primarySource == .localFile)
}

@Test func fallbackReturnsOfficialWhenLocalEmpty() async {
    let official = snapshot(.codex, status: .noData)
    let local = snapshot(.codex, status: .noData, source: .localLog)
    let provider = FallbackProvider(
        primary: StubProvider(providerID: .codex, result: official),
        fallback: StubProvider(providerID: .codex, result: local)
    )

    let result = await provider.snapshot()
    #expect(result.status == .noData)
    #expect(result.usageRows.isEmpty)
}
