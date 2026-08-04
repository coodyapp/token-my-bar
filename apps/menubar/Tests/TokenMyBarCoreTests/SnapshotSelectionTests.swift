import Foundation
import Testing
@testable import TokenMyBarCore

private func snap(_ id: ProviderID, percent: Double? = nil) -> ProviderSnapshot {
    ProviderSnapshot(
        providerID: id,
        status: .ok,
        usedTokens: nil,
        usagePercent: percent,
        primarySource: .oauth,
        confidence: .high,
        isEstimated: false
    )
}

@Test func selectionPrefersTheNamedVendor() {
    let outcome = SnapshotSelection.select(
        from: [snap(.codex), snap(.claudeCode)], vendor: "claude", primary: nil, combined: nil
    )
    if case .snapshot(let s) = outcome {
        #expect(s.providerID == .claudeCode)
    } else {
        Issue.record("expected a snapshot, got \(outcome)")
    }
}

@Test func selectionReportsAnUnknownVendorAsAUsageError() {
    let outcome = SnapshotSelection.select(from: [snap(.codex)], vendor: "gpt5", primary: nil, combined: nil)
    #expect(outcome == .unknownVendor("gpt5"))
}

@Test func selectionReportsAMissingVendorAsUnavailableNotAUsageError() {
    // A vendor absent from the cache (disabled in the app, never fetched) is a
    // data condition: the CLI still owes Waybar a parseable payload.
    let outcome = SnapshotSelection.select(from: [snap(.codex)], vendor: "antigravity", primary: nil, combined: nil)
    #expect(outcome == .unavailable(.antigravity))
}

@Test func selectionFallsBackThroughPrimaryThenCombinedThenFirst() {
    let codex = snap(.codex, percent: 10)
    let claude = snap(.claudeCode, percent: 20)
    if case .snapshot(let s) = SnapshotSelection.select(from: [codex, claude], vendor: nil, primary: .claudeCode, combined: nil) {
        #expect(s.providerID == .claudeCode)
    } else {
        Issue.record("expected a snapshot")
    }
    if case .snapshot(let s) = SnapshotSelection.select(from: [codex, claude], vendor: nil, primary: nil, combined: claude) {
        #expect(s.providerID == .claudeCode)
    } else {
        Issue.record("expected a snapshot")
    }
    #expect(SnapshotSelection.select(from: [], vendor: nil, primary: nil, combined: nil) == .unavailable(nil))
}

@Test func selectionPlaceholderKeepsTheWaybarContract() {
    let vendored = SnapshotSelection.placeholderReport(for: .antigravity)
    #expect(vendored.vendor == "antigravity")
    #expect(vendored.status == "no-data")
    #expect(vendored.text == "Antigravity --")
    #expect(vendored.tooltip.contains("--refresh"))

    let generic = SnapshotSelection.placeholderReport(for: nil)
    #expect(generic.vendor == "none")
    #expect(generic.cssClass == "no-data")
}
