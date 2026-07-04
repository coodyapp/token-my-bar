#if os(macOS)
import AppKit
import SwiftUI
import TokenMyBarCore

/// Owns the Settings `NSWindow` so it survives close/reopen and stays a single
/// instance. SwiftUI content is hosted via `NSHostingController`.
@MainActor
final class SettingsWindowController {
    private let window: NSWindow

    init(
        settings: AppSettings,
        launchAtLogin: LaunchAtLoginManager,
        onRefreshIntervalChange: @escaping () -> Void,
        onVendorsChange: @escaping () -> Void,
        onDisplayPreferencesChange: @escaping () -> Void
    ) {
        let view = SettingsView(
            model: SettingsModel(
                settings: settings,
                launchAtLogin: launchAtLogin,
                onRefreshIntervalChange: onRefreshIntervalChange,
                onVendorsChange: onVendorsChange,
                onDisplayPreferencesChange: onDisplayPreferencesChange
            )
        )
        let hosting = NSHostingController(rootView: view)
        window = NSWindow(contentViewController: hosting)
        window.title = "TokenMyBar Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 520, height: 660))
        window.center()
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}

@MainActor
final class SettingsModel: ObservableObject {
    @Published var refreshInterval: RefreshInterval {
        didSet {
            settings.refreshInterval = refreshInterval
            onRefreshIntervalChange()
        }
    }

    @Published var launchAtLoginEnabled: Bool {
        didSet {
            launchAtLogin.setEnabled(launchAtLoginEnabled)
            let actual = launchAtLogin.isEnabled
            settings.launchAtLogin = actual
            if actual != launchAtLoginEnabled {
                launchAtLoginEnabled = actual
            }
        }
    }

    @Published var enabledVendors: Set<ProviderID> {
        didSet {
            for id in ProviderID.allCases {
                settings.setProvider(id, enabled: enabledVendors.contains(id))
            }
            onVendorsChange()
        }
    }

    @Published var displayMode: DisplayMode {
        didSet { settings.displayMode = displayMode; onDisplayPreferencesChange() }
    }

    @Published var summaryCalculation: SummaryCalculation {
        didSet { settings.summaryCalculation = summaryCalculation; onDisplayPreferencesChange() }
    }

    @Published var hideLabelsWhenSpaceLimited: Bool {
        didSet { settings.hideLabelsWhenSpaceLimited = hideLabelsWhenSpaceLimited; onDisplayPreferencesChange() }
    }

    @Published var collapseToSummaryAutomatically: Bool {
        didSet { settings.collapseToSummaryAutomatically = collapseToSummaryAutomatically; onDisplayPreferencesChange() }
    }

    @Published var showProviderOrder: Bool {
        didSet { settings.showProviderOrder = showProviderOrder; onDisplayPreferencesChange() }
    }

    @Published var showColoredUsageIndicators: Bool {
        didSet { settings.showColoredUsageIndicators = showColoredUsageIndicators; onDisplayPreferencesChange() }
    }

    @Published var monochromeIcons: Bool {
        didSet { settings.monochromeIcons = monochromeIcons; onDisplayPreferencesChange() }
    }

    private let settings: AppSettings
    private let launchAtLogin: LaunchAtLoginManager
    private let onRefreshIntervalChange: () -> Void
    private let onVendorsChange: () -> Void
    private let onDisplayPreferencesChange: () -> Void

    init(
        settings: AppSettings,
        launchAtLogin: LaunchAtLoginManager,
        onRefreshIntervalChange: @escaping () -> Void,
        onVendorsChange: @escaping () -> Void,
        onDisplayPreferencesChange: @escaping () -> Void
    ) {
        self.settings = settings
        self.launchAtLogin = launchAtLogin
        self.onRefreshIntervalChange = onRefreshIntervalChange
        self.onVendorsChange = onVendorsChange
        self.onDisplayPreferencesChange = onDisplayPreferencesChange
        self.refreshInterval = settings.refreshInterval
        self.launchAtLoginEnabled = launchAtLogin.isEnabled
        self.enabledVendors = Set(settings.enabledProviders)
        self.displayMode = settings.displayMode
        self.summaryCalculation = settings.summaryCalculation
        self.hideLabelsWhenSpaceLimited = settings.hideLabelsWhenSpaceLimited
        self.collapseToSummaryAutomatically = settings.collapseToSummaryAutomatically
        self.showProviderOrder = settings.showProviderOrder
        self.showColoredUsageIndicators = settings.showColoredUsageIndicators
        self.monochromeIcons = settings.monochromeIcons
    }

    func bindingForVendor(_ id: ProviderID) -> Binding<Bool> {
        Binding(
            get: { self.enabledVendors.contains(id) },
            set: { isOn in
                if isOn {
                    self.enabledVendors.insert(id)
                } else {
                    self.enabledVendors.remove(id)
                }
            }
        )
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("Display") {
                Picker("Display Mode", selection: $model.displayMode) {
                    ForEach(DisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            Section("Vendors") {
                ForEach(ProviderID.allCases, id: \.self) { id in
                    Toggle(id.displayName, isOn: model.bindingForVendor(id))
                }
            }

            Section("Summary Calculation") {
                Picker("Summary", selection: $model.summaryCalculation) {
                    ForEach(SummaryCalculation.allCases) { calculation in
                        Text(calculation.title).tag(calculation)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }

            Section("Menu Bar Behavior") {
                Toggle("Hide labels when space is limited", isOn: $model.hideLabelsWhenSpaceLimited)
                Toggle("Collapse to summary automatically", isOn: $model.collapseToSummaryAutomatically)
                Toggle("Show provider order", isOn: $model.showProviderOrder)
                Toggle("Show colored usage indicators", isOn: $model.showColoredUsageIndicators)
                Toggle("Monochrome icons (follow macOS menu bar style)", isOn: $model.monochromeIcons)
            }

            Section("Refresh") {
                Picker("Update", selection: $model.refreshInterval) {
                    ForEach(RefreshInterval.allCases) { interval in
                        Text(interval.title).tag(interval)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $model.launchAtLoginEnabled)
            }

            Section {
                Text("TokenMyBar reads usage from your existing vendor sessions on this Mac. No data leaves your device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .frame(minHeight: 660)
        .tint(.accentColor)
    }
}
#endif
