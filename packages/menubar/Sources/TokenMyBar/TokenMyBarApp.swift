#if os(macOS)
import AppKit
import ServiceManagement
import SwiftUI
import TokenMyBarCore

@main
struct TokenMyBarApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let settings = AppSettings()
    private let refresher = UsageRefresher()
    private var config = AppConfig.load()
    private let launchAtLogin = LaunchAtLoginManager()
    private var settingsWindowController: SettingsWindowController?
    private var refreshTimer: Timer?
    private var snapshots: [ProviderSnapshot] = []
    private var isRefreshing = false
    private var popoverContentSize = NSSize(width: 340, height: 420)

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "TokenMyBarStatusItem"
        if let button = item.button {
            button.title = "--"
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityTitle("TokenMyBar usage")
            button.toolTip = "TokenMyBar — AI token usage"
        }
        statusItem = item

        popover.behavior = .transient
        popover.animates = false
        popover.contentSize = popoverContentSize

        render()
        scheduleRefreshTimer()

        Task {
            snapshots = await refresher.cached()
            render()
            await refresh()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        popover.performClose(nil)
    }

    // MARK: Status item interaction

    @objc private func statusItemClicked() {
        let isRightClick = NSApp.currentEvent?.type == .rightMouseUp
            || NSApp.currentEvent?.modifierFlags.contains(.control) == true
        if isRightClick {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popoverContentSize = preferredPopoverSize(for: button)
            popover.contentSize = popoverContentSize
            render()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func preferredPopoverSize(for button: NSStatusBarButton) -> NSSize {
        let screen = button.window?.screen ?? NSScreen.main
        let visibleHeight = screen?.visibleFrame.height ?? 900
        let height = max(320, min(420, visibleHeight - 96))
        return NSSize(width: 340, height: height)
    }

    private func showContextMenu() {
        guard let statusItem else { return }
        let menu = makeContextMenu()
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
    }

    func menuDidClose(_ menu: NSMenu) {
        // Detach the menu so the next left-click opens the popover again.
        statusItem?.menu = nil
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        let refreshItem = NSMenuItem(title: isRefreshing ? "Refreshing…" : "Refresh", action: #selector(refreshFromMenu), keyEquivalent: "r")
        refreshItem.target = self
        refreshItem.isEnabled = !isRefreshing
        menu.addItem(refreshItem)

        menu.addItem(.separator())

        let launchItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.target = self
        launchItem.state = launchAtLogin.isEnabled ? .on : .off
        menu.addItem(launchItem)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let aboutItem = NSMenuItem(title: "About TokenMyBar", action: #selector(openAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit TokenMyBar", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    // MARK: Actions

    @objc private func refreshFromMenu() {
        Task { await refresh(force: true) }
    }

    @objc private func toggleLaunchAtLogin() {
        let enable = !launchAtLogin.isEnabled
        launchAtLogin.setEnabled(enable)
        settings.launchAtLogin = launchAtLogin.isEnabled
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                settings: settings,
                launchAtLogin: launchAtLogin,
                onRefreshIntervalChange: { [weak self] in self?.scheduleRefreshTimer() },
                onVendorsChange: { [weak self] in Task { await self?.refresh(force: true) } }
            )
        }
        settingsWindowController?.show()
    }

    @objc private func openAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: aboutPanelOptions())
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func aboutPanelOptions() -> [NSApplication.AboutPanelOptionKey: Any] {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
        let credits = NSAttributedString(
            string: "Live AI token usage for Codex, Claude Code, and OpenCode — right in your menu bar.",
            attributes: [.font: NSFont.systemFont(ofSize: 11)]
        )
        return [
            .applicationName: "TokenMyBar",
            .applicationVersion: version,
            .credits: credits,
        ]
    }

    // MARK: Refresh

    private func scheduleRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        guard let seconds = settings.refreshInterval.seconds else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.refresh() }
        }
    }

    private func refresh(force: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        render()
        config = AppConfig.load()
        let next = await refresher.refresh(
            enabled: settings.enabledProviders,
            ttl: force ? 0 : config.refreshTTL
        )
        snapshots = next
        isRefreshing = false
        render()
    }

    private func render() {
        if let button = statusItem?.button {
            button.image = nil
            button.attributedTitle = statusTitle()
        }

        let actions = PopoverActions(
            isRefreshing: isRefreshing,
            onRefresh: { [weak self] in self?.refreshFromMenu() },
            onSettings: { [weak self] in self?.openSettings() },
            onAbout: { [weak self] in self?.openAbout() },
            onQuit: { [weak self] in self?.quit() }
        )
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(
                snapshots: snapshots,
                actions: actions,
                contentHeight: popoverContentSize.height - 20
            )
        )
    }

    private func statusTitle() -> NSAttributedString {
        let segments = statusSegments()
        if segments.isEmpty {
            return statusSegment(iconName: "chart.bar.xaxis", title: "--")
        }

        let title = NSMutableAttributedString()
        for (index, segment) in segments.enumerated() {
            if index > 0 {
                title.append(NSAttributedString(string: "  "))
            }
            title.append(statusSegment(iconName: iconName(for: segment.providerID), title: segment.title))
        }
        return title
    }

    private func statusSegments() -> [(providerID: ProviderID, title: String)] {
        let usable = snapshots.filter { $0.status == .ok || $0.status == .stale }
        let ordered: [ProviderSnapshot]
        if let primary = config.primaryVendor, let primarySnapshot = usable.first(where: { $0.providerID == primary }) {
            ordered = [primarySnapshot] + usable.filter { $0.providerID != primary }
        } else {
            ordered = usable
        }

        return ordered.compactMap { snapshot in
            guard let percent = snapshot.usagePercent else { return nil }
            return (snapshot.providerID, "\(Int(percent.rounded()))%")
        }
    }

    private func statusSegment(iconName: String, title: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        if let image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil) {
            let attachment = NSTextAttachment()
            attachment.image = image
            attachment.bounds = NSRect(x: 0, y: -2, width: 14, height: 14)
            result.append(NSAttributedString(attachment: attachment))
            result.append(NSAttributedString(string: " "))
        }
        result.append(NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
            ]
        ))
        return result
    }

    private func iconName(for providerID: ProviderID) -> String {
        switch providerID {
        case .codex: "terminal"
        case .claudeCode: "sparkles"
        case .opencode: "chevron.left.forwardslash.chevron.right"
        }
    }
}
#else
@main
struct TokenMyBarApp {
    static func main() {
        print("TokenMyBar menubar app requires macOS.")
    }
}
#endif
