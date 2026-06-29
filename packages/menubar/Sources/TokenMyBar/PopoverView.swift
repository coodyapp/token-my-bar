#if os(macOS)
import SwiftUI
import TokenMyBarCore

struct PopoverActions {
    var isRefreshing: Bool
    var onRefresh: () -> Void
    var onSettings: () -> Void
    var onAbout: () -> Void
    var onQuit: () -> Void
}

struct PopoverView: View {
    let snapshots: [ProviderSnapshot]
    let actions: PopoverActions
    let contentHeight: CGFloat
    @State private var didAppear = false

    private var activeSnapshots: [ProviderSnapshot] {
        snapshots.filter { $0.status == .ok || $0.status == .stale }
    }

    private var updatedText: String {
        guard let date = snapshots.map(\.refreshedAt).max() else { return "never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 620, height: contentHeight)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(10)
        .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
        .scaleEffect(didAppear ? 1 : 0.985, anchor: .topTrailing)
        .offset(x: didAppear ? 0 : 28)
        .opacity(didAppear ? 1 : 0)
        .animation(.spring(response: 0.32, dampingFraction: 0.9), value: didAppear)
        .onAppear { didAppear = true }
        .onDisappear { didAppear = false }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.red)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 5) {
                Text("TokenMyBar")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.primary)
                Label("Updated \(updatedText)", systemImage: "clock")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            }
            Spacer()
            Button(action: actions.onRefresh) {
                ZStack {
                    if actions.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.62)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 18, weight: .semibold))
                    }
                }
                .frame(width: 34, height: 34)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.primary)
            .disabled(actions.isRefreshing)
            .keyboardShortcut("r", modifiers: .command)
            .accessibilityLabel(actions.isRefreshing ? "Refreshing" : "Refresh")

            Menu {
                Button("Settings…", action: actions.onSettings)
                Button("About TokenMyBar", action: actions.onAbout)
                Divider()
                Button("Quit TokenMyBar", action: actions.onQuit)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.primary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More actions")
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 18)
    }

    @ViewBuilder
    private var content: some View {
        if activeSnapshots.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "tray")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("No active vendors")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("Enable a vendor in Settings or refresh usage.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 18) {
                        Color.clear
                            .frame(height: 0)
                            .id("top")
                        ForEach(Array(activeSnapshots.enumerated()), id: \.element.id) { index, snapshot in
                            VendorSection(snapshot: snapshot)
                            if index < activeSnapshots.count - 1 {
                                Divider()
                                    .overlay(Color(nsColor: .separatorColor).opacity(0.55))
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 18)
                }
                .onAppear {
                    DispatchQueue.main.async {
                        proxy.scrollTo("top", anchor: .top)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text("Usage resets are based on each vendor's schedule.")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Manage Tokens…", action: actions.onSettings)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

}

private struct VendorSection: View {
    let snapshot: ProviderSnapshot

    private var isStale: Bool { snapshot.status == .stale || snapshot.status == .error }

    private var rows: [UsageRow] {
        if !snapshot.usageRows.isEmpty { return snapshot.usageRows }
        return [UsageRow(key: "status", title: snapshot.displayName, subtitle: snapshot.message, value: snapshot.status.label)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: iconName)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 28)
                Text(snapshot.displayName)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.primary)
                if let plan = snapshot.planName {
                    Text(plan)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(snapshot.status.label)
                    .font(.system(size: 14, weight: .bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(statusColor.opacity(0.18), in: Capsule())
                    .foregroundStyle(statusColor)
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            if let authSummary = snapshot.authSummary {
                Text(authSummary)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 40)
            }

            VStack(spacing: 18) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    UsageRowView(row: row, isStale: isStale)
                }
            }
        }
    }

    private var iconName: String {
        switch snapshot.providerID {
        case .codex: "terminal"
        case .claudeCode: "sparkles"
        case .opencode: "chevron.left.forwardslash.chevron.right"
        }
    }

    private var statusColor: Color {
        switch snapshot.status {
        case .ok: .green
        case .loading, .stale, .noData: .orange
        case .unauthenticated, .error: .red
        }
    }
}

private struct UsageRowView: View {
    let row: UsageRow
    let isStale: Bool

    private var clampedPercent: Double? {
        row.percent.map { min(max($0, 0), 100) }
    }

    private var barColor: Color {
        switch UsageSeverity(percent: row.percent) {
        case .normal: .accentColor
        case .warning: .orange
        case .critical: .red
        }
    }

    private var usedText: String {
        // Left caption under the bar: prefer an explicit subtitle (e.g. "$x / $y"),
        // otherwise show "<percent>% used", otherwise the raw value.
        if let subtitle = row.subtitle { return subtitle }
        if let percent = row.percent { return "\(Int(percent.rounded()))% used" }
        return row.value
    }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
            GridRow(alignment: .center) {
                if let iconName = row.iconName {
                    Image(systemName: iconName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26)
                } else {
                    Color.clear.frame(width: 26)
                }
                Text(row.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary)
                    .gridCellColumns(2)
            }

            GridRow(alignment: .center) {
                Color.clear.frame(width: 26)
                Text(usedText)
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .leading)
                UsageMeter(percent: clampedPercent ?? 0, color: isStale ? .secondary : barColor)
                    .frame(height: 5)
                if let detail = row.detail {
                    Text(detail)
                        .font(.system(size: 14, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 110, alignment: .trailing)
                } else {
                    Color.clear.frame(width: 110)
                }
            }
        }
    }
}

private struct UsageMeter: View {
    let percent: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let width = max(8, proxy.size.width * min(max(percent, 0), 100) / 100)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(nsColor: .separatorColor).opacity(0.30))
                Capsule()
                    .fill(color)
                    .frame(width: width)
            }
        }
    }
}

private extension ProviderStatus {
    var label: String {
        switch self {
        case .ok: "OK"
        case .loading: "Loading"
        case .stale: "Stale"
        case .noData: "No data"
        case .unauthenticated: "Sign in"
        case .error: "Error"
        }
    }
}
#endif
