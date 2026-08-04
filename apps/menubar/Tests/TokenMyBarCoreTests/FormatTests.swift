import Testing
@testable import TokenMyBarCore

@Test func formatCountRoundsToNearestUnit() {
    #expect(Format.count(999) == "999")
    #expect(Format.count(1_499) == "1K")
    #expect(Format.count(1_500) == "2K")
    #expect(Format.count(1_999_999) == "2M")
}

@Test func formatCountRollsOverKToMAtBoundary() {
    // Values in 999_500...999_999 round to 1000 in the K branch and must
    // display "1M", never "1000K".
    #expect(Format.count(999_999) == "1M")
    #expect(Format.count(999_500) == "1M")
    #expect(Format.count(999_499) == "999K")
}

@Test func formatPercentRoundsLikeTheVisibleLabel() {
    // One formatter for the label and the accessibility value: truncation
    // made VoiceOver say 69% where the screen showed 70%.
    #expect(Format.percent(69.6) == "70%")
    #expect(Format.percent(99.6) == "100%")
    #expect(Format.percent(0) == "0%")
    #expect(Format.percent(.nan) == "—")
}

@Test func spokenStatusTitleCarriesTheLiveNumbers() {
    // The status item's accessibility title must follow the rendered numbers,
    // not stay frozen at the launch-time "TokenMyBar usage".
    let segments = [
        MenuBarHeadline(providerID: .claudeCode, percent: 42.4, windowLabel: "5h", isStale: false),
        MenuBarHeadline(providerID: .codex, percent: 61, windowLabel: "wk", isStale: true),
    ]
    #expect(MenuBarHeadline.spokenTitle(for: segments)
        == "TokenMyBar usage: Claude Code 42% (5h), OpenAI Codex 61% (wk), stale")
    #expect(MenuBarHeadline.spokenTitle(for: []) == "TokenMyBar usage")
}
