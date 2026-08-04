import Foundation
import Testing
@testable import TokenMyBarCore

private func snap(
    _ id: ProviderID,
    status: ProviderStatus = .ok,
    percent: Double? = nil,
    rows: [UsageRow] = []
) -> ProviderSnapshot {
    ProviderSnapshot(
        providerID: id,
        status: status,
        usedTokens: nil,
        usagePercent: percent,
        primarySource: .oauth,
        confidence: .high,
        isEstimated: false,
        usageRows: rows
    )
}

private func row(_ key: String, _ percent: Double?, resetIn: TimeInterval? = 3600, now: Date = Date()) -> UsageRow {
    UsageRow(
        key: key,
        title: key.capitalized,
        value: percent.map { "\(Int($0))%" } ?? "—",
        resetAt: resetIn.map { now.addingTimeInterval($0) },
        percent: percent
    )
}

@Test func headlineReportsTheWorstWindowNotTheSession() {
    // The session window is near zero between sessions, which is exactly when
    // someone glances at the bar. Reporting it hides an exhausted week.
    let snapshot = snap(.codex, percent: 0, rows: [row("session", 0), row("weekly", 100)])

    let headline = MenuBarHeadline.from(snapshot)

    #expect(headline?.percentText == "100%")
    #expect(headline?.windowLabel == "wk")
}

@Test func headlineNamesTheWindowItCameFrom() {
    #expect(MenuBarHeadline.from(snap(.claudeCode, rows: [row("session", 42)]))?.windowLabel == "5h")
    #expect(MenuBarHeadline.from(snap(.opencode, rows: [row("monthly", 61)]))?.windowLabel == "mo")
    #expect(MenuBarHeadline.from(snap(.claudeCode, rows: [row("seven_day_fable", 7)]))?.windowLabel == "wk")
}

@Test func headlineDropsWindowsThatHaveAlreadyRolledOver() {
    // A cached weekly at 100% whose reset passed describes a period that is over;
    // showing it as the current load is how stale data reads as an emergency —
    // and its inverse, a spent week reading as a quiet morning.
    let snapshot = snap(.codex, status: .unauthenticated, percent: 76, rows: [
        row("session", 76, resetIn: -60 * 60 * 24),
        row("weekly", 100, resetIn: -60 * 60 * 24),
    ])

    #expect(MenuBarHeadline.from(snapshot) == nil)
}

@Test func headlineMarksNonCurrentReadingsStale() {
    #expect(MenuBarHeadline.from(snap(.codex, rows: [row("session", 10)]))?.isStale == false)
    #expect(MenuBarHeadline.from(snap(.codex, status: .stale, rows: [row("session", 10)]))?.isStale == true)
    #expect(MenuBarHeadline.from(snap(.codex, status: .unauthenticated, rows: [row("session", 10)]))?.isStale == true)
}

@Test func headlineIgnoresWindowsWithNoReadablePercent() {
    // A renamed percent field yields no percent; it must not become the headline
    // as 0%, which would read as "nothing used".
    let snapshot = snap(.claudeCode, rows: [row("session", nil), row("weekly", 30)])

    #expect(MenuBarHeadline.from(snapshot)?.percentText == "30%")
}

@Test func headlineFallsBackToTheSnapshotPercentWhenThereAreNoWindows() {
    // Vendors that report only a headline percent (no per-window rows) still show.
    #expect(MenuBarHeadline.from(snap(.opencode, percent: 12))?.percentText == "12%")
    #expect(MenuBarHeadline.from(snap(.opencode))?.percentText == nil)
}

@Test func attentionFlagsVendorsThatVanishedWithNumbers() {
    // A vendor whose windows all elapsed produces no headline (deliberate),
    // so it must raise the warning glyph instead of silently vanishing while
    // the other vendors keep showing figures.
    let vanished = snap(.codex, status: .stale, rows: [row("weekly", 100, resetIn: -60)])
    let fresh = snap(.claudeCode, status: .ok, rows: [row("weekly", 100, resetIn: -60)])

    #expect(MenuBarHeadline.from(vanished) == nil)
    #expect(MenuBarHeadline.needsAttention([vanished], shown: []))
    #expect(MenuBarHeadline.needsAttention([fresh], shown: []))
}

@Test func attentionFlagsUnauthenticatedAndErroredVendorsButNotShownOnes() {
    let unauth = snap(.codex, status: .unauthenticated)
    #expect(MenuBarHeadline.needsAttention([unauth], shown: []))
    #expect(!MenuBarHeadline.needsAttention([unauth], shown: [.codex]))
}

@Test func attentionIgnoresVendorsWithNothingToShow() {
    // .noData with no numbers is an ordinary empty account, not a failure —
    // and a headline-producing vendor is already on screen.
    #expect(!MenuBarHeadline.needsAttention([snap(.opencode, status: .noData)], shown: []))
    #expect(!MenuBarHeadline.needsAttention([snap(.opencode, status: .ok, percent: 12)], shown: [.opencode]))
}
