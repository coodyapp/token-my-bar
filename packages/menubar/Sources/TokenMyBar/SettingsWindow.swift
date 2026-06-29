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
        onVendorsChange: @escaping () -> Void
    ) {
        let view = SettingsView(
            model: SettingsModel(
                settings: settings,
                launchAtLogin: launchAtLogin,
                onRefreshIntervalChange: onRefreshIntervalChange,
                onVendorsChange: onVendorsChange
            )
        )
        let hosting = NSHostingController(rootView: view)
        window = NSWindow(contentViewController: hosting)
        window.title = "TokenMyBar Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 460, height: 420))
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

    private let settings: AppSettings
    private let launchAtLogin: LaunchAtLoginManager
    private let onRefreshIntervalChange: () -> Void
    private let onVendorsChange: () -> Void

    init(
        settings: AppSettings,
        launchAtLogin: LaunchAtLoginManager,
        onRefreshIntervalChange: @escaping () -> Void,
        onVendorsChange: @escaping () -> Void
    ) {
        self.settings = settings
        self.launchAtLogin = launchAtLogin
        self.onRefreshIntervalChange = onRefreshIntervalChange
        self.onVendorsChange = onVendorsChange
        self.refreshInterval = settings.refreshInterval
        self.launchAtLoginEnabled = launchAtLogin.isEnabled
        self.enabledVendors = Set(settings.enabledProviders)
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
            Section("Vendors") {
                ForEach(ProviderID.allCases, id: \.self) { id in
                    Toggle(id.displayName, isOn: model.bindingForVendor(id))
                }
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
        .frame(width: 460, height: 420)
        .tint(.accentColor)
    }
}
#endif
