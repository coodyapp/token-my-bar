#if os(macOS) && DEBUG
import AppKit
import SwiftUI
import TokenMyBarCore

/// Dev-only: renders the popover to a PNG via ImageRenderer (no screen capture needed).
/// Activated by launching with the `TMB_SNAPSHOT=/path/out.png` environment variable.
///
/// `TMB_SNAPSHOT_STATE` picks which state to draw — `ok` (default), `degraded`,
/// `loading`, or `empty` — because the states a user is most likely to be
/// confused by are the ones a happy-path-only preview never shows.
@MainActor
enum PreviewSnapshot {
    enum State: String {
        case ok
        case degraded
        case loading
        case empty
    }

    static func renderIfRequested() -> Bool {
        guard let path = ProcessInfo.processInfo.environment["TMB_SNAPSHOT"] else { return false }
        let state = ProcessInfo.processInfo.environment["TMB_SNAPSHOT_STATE"]
            .flatMap(State.init(rawValue:)) ?? .ok
        render(to: path, state: state)
        return true
    }

    static func render(to path: String, state: State = .ok) {
        let actions = PopoverActions(
            isRefreshing: state == .loading,
            onRefresh: {}, onSettings: {}, onAbout: {}, onQuit: {}
        )
        let content = PopoverView(snapshots: snapshots(for: state), actions: actions)
            .environment(\.colorScheme, .dark)
            .background(Color.black)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2

        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("snapshot: render failed\n".utf8))
            return
        }
        try? png.write(to: URL(fileURLWithPath: path))
        FileHandle.standardError.write(Data("snapshot: wrote \(path)\n".utf8))
    }

    private static func snapshots(for state: State) -> [ProviderSnapshot] {
        switch state {
        case .ok: mockSnapshots
        case .degraded: degradedSnapshots
        case .loading, .empty: []
        }
    }

    /// The states worth eyeballing before a release: expired auth still showing
    /// its last-known numbers, a vendor that failed outright, and one with no
    /// data yet.
    private static var degradedSnapshots: [ProviderSnapshot] {
        [
            // Cached numbers whose windows rolled over weeks ago — the state that
            // used to render identically to a live reading.
            ProviderSnapshot(
                providerID: .codex, status: .stale, usedTokens: nil, usagePercent: 76,
                refreshedAt: Date().addingTimeInterval(-25 * 24 * 3600),
                primarySource: .oauth, confidence: .low, isEstimated: false,
                message: "Using cached data; latest refresh returned error", planName: "Plus",
                usageRows: [
                    UsageRow(key: "session", title: "Session", value: "76%", resetAt: Date().addingTimeInterval(-25 * 24 * 3600), percent: 76),
                    UsageRow(key: "weekly", title: "Weekly", value: "100%", resetAt: Date().addingTimeInterval(-18 * 24 * 3600), percent: 100),
                ]
            ),
            ProviderSnapshot(
                providerID: .claudeCode, status: .unauthenticated, usedTokens: nil,
                usagePercent: 42, refreshedAt: Date().addingTimeInterval(-3600),
                primarySource: .oauth, confidence: .high, isEstimated: false,
                message: "Sign in again; showing cached data", planName: "Max 5x",
                usageRows: [
                    UsageRow(key: "session", title: "Session", value: "42%", resetAt: Date().addingTimeInterval(2 * 3600 + 300), percent: 42),
                    UsageRow(key: "weekly", title: "Weekly", value: "61%", resetAt: Date().addingTimeInterval(3 * 24 * 3600 + 3600), percent: 61),
                    UsageRow(key: "seven_day_fable", title: "Fable only", value: "—", resetAt: Date().addingTimeInterval(3 * 24 * 3600), percent: nil),
                ]
            ),
            ProviderSnapshot(
                providerID: .opencode, status: .noData, usedTokens: nil,
                primarySource: .localFile, confidence: .low, isEstimated: true,
                message: "OpenCode database found, but no token usage yet"
            ),
        ]
    }

    private static var mockSnapshots: [ProviderSnapshot] {
        let now = Date().addingTimeInterval(-120)
        func row(_ key: String, _ title: String, _ reset: String, _ pct: Double) -> UsageRow {
            UsageRow(key: key, title: title, value: "\(Int(pct))%", detail: reset, percent: pct)
        }
        return [
            ProviderSnapshot(
                providerID: .opencode, status: .ok, usedTokens: 0,
                refreshedAt: now, primarySource: .localFile, confidence: .medium, isEstimated: false,
                usageRows: [
                    row("session", "Rolling Usage", "Resets in 5h 0m", 0),
                    row("weekly", "Weekly", "Resets in 6d 2h", 80),
                    row("monthly", "Monthly", "Resets in 22d 20h", 100),
                ]
            ),
            ProviderSnapshot(
                providerID: .codex, status: .ok, usedTokens: 0,
                refreshedAt: now, primarySource: .oauth, confidence: .high, isEstimated: false,
                planName: "Plus",
                usageRows: [
                    row("session", "Session", "Resets in 3h 2m", 27),
                    row("weekly", "Weekly", "Resets in 6d 4h", 14),
                    row("monthly", "Monthly", "Resets in 22d 21h", 5),
                ]
            ),
            ProviderSnapshot(
                providerID: .claudeCode, status: .ok, usedTokens: 0,
                refreshedAt: now, primarySource: .oauth, confidence: .high, isEstimated: false,
                usageRows: [
                    row("session", "Session", "Resets in 1h 12m", 82),
                    row("weekly", "Weekly", "Resets in 2d 18h", 65),
                    row("monthly", "Monthly", "Resets in 18d 6h", 42),
                ]
            ),
        ]
    }
}
#endif
