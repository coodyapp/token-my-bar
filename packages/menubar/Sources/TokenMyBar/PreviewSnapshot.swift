#if os(macOS) && DEBUG
import AppKit
import SwiftUI
import TokenMyBarCore

/// Dev-only: renders the popover to a PNG via ImageRenderer (no screen capture needed).
/// Activated by launching with the `TMB_SNAPSHOT=/path/out.png` environment variable.
@MainActor
enum PreviewSnapshot {
    static func renderIfRequested() -> Bool {
        guard let path = ProcessInfo.processInfo.environment["TMB_SNAPSHOT"] else { return false }
        render(to: path)
        return true
    }

    static func render(to path: String) {
        let actions = PopoverActions(
            isRefreshing: false,
            onRefresh: {}, onSettings: {}, onAbout: {}, onQuit: {}
        )
        let content = PopoverView(snapshots: mockSnapshots, actions: actions)
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
