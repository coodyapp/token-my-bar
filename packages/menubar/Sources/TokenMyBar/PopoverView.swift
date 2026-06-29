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
        .frame(width: 430, height: 560)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.separator.opacity(0.55), lineWidth: 1)
        )
        .padding(10)
        .shadow(color: .black.opacity(0.18), radius: 20, y: 8)
        .offset(x: didAppear ? 0 : -22)
        .opacity(didAppear ? 1 : 0)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: didAppear)
        .onAppear { didAppear = true }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("TokenMyBar")
                    .font(.headline)
                Text("AI token usage")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button("Settings…", action: actions.onSettings)
                Button("About TokenMyBar", action: actions.onAbout)
                Divider()
                Button("Quit TokenMyBar", action: actions.onQuit)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More actions")
        }
        .padding(14)
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
                Text("Enable a vendor in Settings or refresh usage.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 12) {
                    ForEach(activeSnapshots) { snapshot in
                        VendorPanel(snapshot: snapshot)
                    }
                }
                .padding(14)
            }
        }
    }

    private var footer: some View {
        HStack {
            Label("Updated \(updatedText)", systemImage: "clock")
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: actions.onRefresh) {
                HStack(spacing: 6) {
                    if actions.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.65)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(actions.isRefreshing ? "Refreshing" : "Refresh")
                }
                .frame(minWidth: 92)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(Color.accentColor)
            .disabled(actions.isRefreshing)
            .keyboardShortcut("r", modifiers: .command)
        }
        .font(.caption)
        .padding(14)
    }
}

private struct VendorPanel: View {
    let snapshot: ProviderSnapshot

    private var isStale: Bool { snapshot.status == .stale || snapshot.status == .error }

    private var rows: [UsageRow] {
        if !snapshot.usageRows.isEmpty { return snapshot.usageRows }
        return [UsageRow(key: "status", title: snapshot.displayName, subtitle: snapshot.message, value: snapshot.status.label)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label(snapshot.displayName, systemImage: iconName)
                    .font(.headline)
                if let plan = snapshot.planName {
                    Text(plan)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(snapshot.status.label)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.14), in: Capsule())
                    .foregroundStyle(statusColor)
            }

            if let authSummary = snapshot.authSummary {
                Text(authSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(rows) { row in
                UsageRowView(row: row, isStale: isStale)
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
        )
    }

    private var iconName: String {
        switch snapshot.providerID {
        case .codex: "terminal"
        case .claudeCode: "sparkles"
        case .opencode: "curlybraces"
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let iconName = row.iconName {
                    Image(systemName: iconName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                }
                Text(row.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if row.percent == nil {
                    Text(row.value)
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(isStale ? .secondary : .primary)
                }
            }

            if let clampedPercent {
                ProgressView(value: clampedPercent, total: 100)
                    .tint(isStale ? .secondary : barColor)
            } else {
                ProgressView(value: 0, total: 100)
                    .tint(.secondary)
                    .opacity(0.25)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(usedText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let detail = row.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
