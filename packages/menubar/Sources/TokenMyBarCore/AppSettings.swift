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

/// Persisted application settings backed by `UserDefaults`.
///
/// Pure value access lives here so it can be unit tested with an in-memory
/// `UserDefaults(suiteName:)`. The menu bar app observes and mutates this store.
public struct AppSettings {
    private enum Key {
        static let refreshInterval = "refreshInterval"
        static let launchAtLogin = "launchAtLogin"
        static let disabledProviders = "disabledProviders"
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
