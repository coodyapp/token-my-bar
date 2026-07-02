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

@Test func appSettingsPersistsLaunchAtLogin() {
    let settings = freshSettings()
    #expect(!settings.launchAtLogin)
    settings.launchAtLogin = true
    #expect(settings.launchAtLogin)
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
