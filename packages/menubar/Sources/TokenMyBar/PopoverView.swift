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
        }
        .frame(width: 320, height: contentHeight)
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
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text("TokenMyBar")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)
                Label("Updated \(updatedText)", systemImage: "clock")
                    .font(.system(size: 12, weight: .semibold))
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
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
                .frame(width: 28, height: 28)
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
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(.primary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More actions")
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
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
                        ForEach(activeSnapshots) { snapshot in
                            VendorSection(snapshot: snapshot)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .onAppear {
                    DispatchQueue.main.async {
                        proxy.scrollTo("top", anchor: .top)
                    }
                }
            }
        }
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 22)
                Text(snapshot.displayName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)
                if let plan = snapshot.planName {
                    Text(plan)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(snapshot.status.label)
                    .font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.18), in: Capsule())
                    .foregroundStyle(statusColor)
            }

            if let authSummary = snapshot.authSummary {
                Text(authSummary)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    UsageRowView(row: row, isStale: isStale)
                    if index < rows.count - 1 {
                        Divider()
                            .overlay(Color(nsColor: .separatorColor).opacity(0.55))
                            .padding(.vertical, 12)
                    }
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let iconName = row.iconName {
                    Image(systemName: iconName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                }
                Text(row.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)
                Spacer()
                if row.percent == nil {
                    Text(row.value)
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(isStale ? .secondary : .primary)
                }
            }

            UsageMeter(percent: clampedPercent ?? 0, color: isStale ? .secondary : barColor)
                .frame(height: 5)

            HStack(alignment: .firstTextBaseline) {
                Text(usedText)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                if let detail = row.detail {
                    Text(detail)
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
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
