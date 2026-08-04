import Foundation
import Testing
@testable import TokenMyBarCore

private func freshSettings() -> AppSettings {
    let suite = "token-my-bar-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    return AppSettings(defaults: defaults)
}

@Test func appSettingsDefaultsToFiveMinuteRefresh() {
    let settings = freshSettings()
    #expect(settings.refreshInterval == .fiveMinutes)
    #expect(settings.refreshInterval.seconds == 300)
}

@Test func appSettingsPersistsRefreshInterval() {
    let settings = freshSettings()
    settings.refreshInterval = .manual
    #expect(settings.refreshInterval == .manual)
    #expect(settings.refreshInterval.seconds == nil)
}

@Test func appSettingsAllProvidersEnabledByDefault() {
    let settings = freshSettings()
    #expect(Set(settings.enabledProviders) == Set(ProviderID.allCases))
    #expect(settings.isProviderEnabled(.codex))
}

@Test func appSettingsDisablesAndReenablesProvider() {
    let settings = freshSettings()
    settings.setProvider(.codex, enabled: false)
    #expect(!settings.isProviderEnabled(.codex))
    #expect(!settings.enabledProviders.contains(.codex))
    #expect(settings.enabledProviders.contains(.opencode))

    settings.setProvider(.codex, enabled: true)
    #expect(settings.isProviderEnabled(.codex))
}

@Test func appSettingsDecodesTheRetiredCustomModeAsIconPercentage() {
    // "Custom" shipped as a selectable mode that rendered identically to
    // Icon + Percentage; the case is gone, but a persisted value must not
    // reset the user's preference store to a crash or surprise.
    let suite = "token-my-bar-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.set("custom", forKey: "displayMode")
    #expect(AppSettings(defaults: defaults).displayMode == .iconPercentage)
}

@Test func effectiveDisplayModePrefersSummaryOverBareIcons() {
    // Summary (one icon + percent) is nearly as narrow as three bare icons
    // and strictly more informative, so it wins when both toggles are on.
    #expect(DisplayMode.effective(explicit: .iconPercentage, hideLabels: true, collapseToSummary: true, segmentCount: 3) == .summary)
    #expect(DisplayMode.effective(explicit: .iconPercentage, hideLabels: false, collapseToSummary: true, segmentCount: 3) == .summary)
    #expect(DisplayMode.effective(explicit: .iconPercentage, hideLabels: true, collapseToSummary: false, segmentCount: 3) == .iconsOnly)
}

@Test func effectiveDisplayModeRespectsAnExplicitChoiceWhenItFits() {
    // Two segments never trip the space heuristics.
    #expect(DisplayMode.effective(explicit: .percentageOnly, hideLabels: true, collapseToSummary: true, segmentCount: 2) == .percentageOnly)
    // An explicit Summary is already as narrow as the heuristics can make it.
    #expect(DisplayMode.effective(explicit: .summary, hideLabels: true, collapseToSummary: false, segmentCount: 3) == .summary)
    // No toggles: the explicit mode stands at any width.
    #expect(DisplayMode.effective(explicit: .iconPercentage, hideLabels: false, collapseToSummary: false, segmentCount: 4) == .iconPercentage)
}

@Test func appSettingsPersistsMenuBarPreferences() {
    let settings = freshSettings()
    #expect(settings.displayMode == .iconPercentage)
    #expect(settings.summaryCalculation == .highestUsage)
    #expect(settings.showProviderOrder)
    #expect(settings.monochromeIcons)

    settings.displayMode = .summary
    settings.summaryCalculation = .averageUsage
    settings.hideLabelsWhenSpaceLimited = true
    settings.collapseToSummaryAutomatically = true
    settings.showProviderOrder = false
    settings.showColoredUsageIndicators = true
    settings.monochromeIcons = false

    #expect(settings.displayMode == .summary)
    #expect(settings.summaryCalculation == .averageUsage)
    #expect(settings.hideLabelsWhenSpaceLimited)
    #expect(settings.collapseToSummaryAutomatically)
    #expect(!settings.showProviderOrder)
    #expect(settings.showColoredUsageIndicators)
    #expect(!settings.monochromeIcons)
}
