import Foundation

/// User-configurable refresh cadence for vendor polling.
public enum RefreshInterval: Int, CaseIterable, Codable, Sendable, Identifiable {
    case manual = 0
    case oneMinute = 60
    case twoMinutes = 120
    case fiveMinutes = 300
    case fifteenMinutes = 900

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .manual: "Manual only"
        case .oneMinute: "Every 1 minute"
        case .twoMinutes: "Every 2 minutes"
        case .fiveMinutes: "Every 5 minutes"
        case .fifteenMinutes: "Every 15 minutes"
        }
    }

    /// Seconds between scheduled refreshes, or `nil` when manual.
    public var seconds: TimeInterval? {
        rawValue == 0 ? nil : TimeInterval(rawValue)
    }
}

public enum DisplayMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case iconPercentage
    case percentageOnly
    case iconsOnly
    case summary
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .iconPercentage: "Icon + Percentage"
        case .percentageOnly: "Percentage Only"
        case .iconsOnly: "Icons Only"
        case .summary: "Summary"
        case .custom: "Custom"
        }
    }
}

public enum SummaryCalculation: String, CaseIterable, Codable, Sendable, Identifiable {
    case highestUsage
    case averageUsage
    case selectedProvider

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .highestUsage: "Highest Usage"
        case .averageUsage: "Average Usage"
        case .selectedProvider: "Selected Provider"
        }
    }
}

/// Persisted application settings backed by `UserDefaults`.
///
/// Pure value access lives here so it can be unit tested with an in-memory
/// `UserDefaults(suiteName:)`. The menu bar app observes and mutates this store.
public struct AppSettings {
    private enum Key {
        static let refreshInterval = "refreshInterval"
        static let launchAtLogin = "launchAtLogin"
        static let disabledProviders = "disabledProviders"
        static let displayMode = "displayMode"
        static let summaryCalculation = "summaryCalculation"
        static let hideLabelsWhenSpaceLimited = "hideLabelsWhenSpaceLimited"
        static let collapseToSummaryAutomatically = "collapseToSummaryAutomatically"
        static let showProviderOrder = "showProviderOrder"
        static let showColoredUsageIndicators = "showColoredUsageIndicators"
        static let monochromeIcons = "monochromeIcons"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var refreshInterval: RefreshInterval {
        get {
            guard defaults.object(forKey: Key.refreshInterval) != nil else { return .fiveMinutes }
            return RefreshInterval(rawValue: defaults.integer(forKey: Key.refreshInterval)) ?? .fiveMinutes
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.refreshInterval) }
    }

    public var launchAtLogin: Bool {
        get { defaults.bool(forKey: Key.launchAtLogin) }
        nonmutating set { defaults.set(newValue, forKey: Key.launchAtLogin) }
    }

    public var displayMode: DisplayMode {
        get {
            guard let raw = defaults.string(forKey: Key.displayMode) else { return .iconPercentage }
            return DisplayMode(rawValue: raw) ?? .iconPercentage
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.displayMode) }
    }

    public var summaryCalculation: SummaryCalculation {
        get {
            guard let raw = defaults.string(forKey: Key.summaryCalculation) else { return .highestUsage }
            return SummaryCalculation(rawValue: raw) ?? .highestUsage
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.summaryCalculation) }
    }

    public var hideLabelsWhenSpaceLimited: Bool {
        get { defaults.bool(forKey: Key.hideLabelsWhenSpaceLimited) }
        nonmutating set { defaults.set(newValue, forKey: Key.hideLabelsWhenSpaceLimited) }
    }

    public var collapseToSummaryAutomatically: Bool {
        get { defaults.bool(forKey: Key.collapseToSummaryAutomatically) }
        nonmutating set { defaults.set(newValue, forKey: Key.collapseToSummaryAutomatically) }
    }

    public var showProviderOrder: Bool {
        get {
            guard defaults.object(forKey: Key.showProviderOrder) != nil else { return true }
            return defaults.bool(forKey: Key.showProviderOrder)
        }
        nonmutating set { defaults.set(newValue, forKey: Key.showProviderOrder) }
    }

    public var showColoredUsageIndicators: Bool {
        get { defaults.bool(forKey: Key.showColoredUsageIndicators) }
        nonmutating set { defaults.set(newValue, forKey: Key.showColoredUsageIndicators) }
    }

    public var monochromeIcons: Bool {
        get {
            guard defaults.object(forKey: Key.monochromeIcons) != nil else { return true }
            return defaults.bool(forKey: Key.monochromeIcons)
        }
        nonmutating set { defaults.set(newValue, forKey: Key.monochromeIcons) }
    }

    public func isProviderEnabled(_ id: ProviderID) -> Bool {
        !disabledProviders.contains(id.rawValue)
    }

    public func setProvider(_ id: ProviderID, enabled: Bool) {
        var disabled = disabledProviders
        if enabled {
            disabled.remove(id.rawValue)
        } else {
            disabled.insert(id.rawValue)
        }
        defaults.set(Array(disabled).sorted(), forKey: Key.disabledProviders)
    }

    public var enabledProviders: [ProviderID] {
        ProviderID.allCases.filter(isProviderEnabled)
    }

    private var disabledProviders: Set<String> {
        Set(defaults.stringArray(forKey: Key.disabledProviders) ?? [])
    }
}
