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
                .overlay(Color(nsColor: .separatorColor).opacity(0.78))
            content
        }
        .frame(width: 372, height: contentHeight)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .scaleEffect(didAppear ? 1 : 0.985, anchor: .topTrailing)
        .offset(x: didAppear ? 0 : 12)
        .opacity(didAppear ? 1 : 0)
        .animation(.spring(response: 0.32, dampingFraction: 0.9), value: didAppear)
        .onAppear { didAppear = true }
        .onDisappear { didAppear = false }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.red.gradient)
                .frame(width: 24, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text("TokenMyBar")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Label("Updated \(updatedText)", systemImage: "clock")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            }
            Spacer()

            HStack(spacing: 8) {
                Button(action: actions.onRefresh) {
                    HeaderIcon(systemName: "arrow.clockwise", isLoading: actions.isRefreshing)
                }
                .buttonStyle(.plain)
                .disabled(actions.isRefreshing)
                .keyboardShortcut("r", modifiers: .command)
                .accessibilityLabel(actions.isRefreshing ? "Refreshing" : "Refresh")

                Menu {
                    Button("Settings…", action: actions.onSettings)
                    Button("About TokenMyBar", action: actions.onAbout)
                    Divider()
                    Button("Quit TokenMyBar", action: actions.onQuit)
                } label: {
                    HeaderIcon(systemName: "gearshape")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("More actions")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var content: some View {
        if activeSnapshots.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "tray")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("No active vendors")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Enable a vendor in Settings or refresh usage.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(activeSnapshots.enumerated()), id: \.element.id) { index, snapshot in
                    VendorSection(snapshot: snapshot)
                    if index < activeSnapshots.count - 1 {
                        Divider()
                            .overlay(Color(nsColor: .separatorColor).opacity(0.82))
                            .padding(.vertical, 10)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
    }

}

private struct HeaderIcon: View {
    let systemName: String
    var isLoading = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.62))
                .overlay(Circle().stroke(Color(nsColor: .separatorColor).opacity(0.48), lineWidth: 1))
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.58)
            } else {
                Image(systemName: systemName)
                    .font(.system(size: 13, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .foregroundStyle(.primary)
        .frame(width: 28, height: 28)
        .contentShape(Circle())
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
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            VStack(alignment: .leading, spacing: 9) {
                ForEach(rows, id: \.id) { row in
                    UsageRowView(row: row, isStale: isStale)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 22)
            HStack(alignment: .center, spacing: 6) {
                Text(snapshot.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                if let plan = snapshot.planName {
                    Text(plan)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color(nsColor: .controlBackgroundColor).opacity(0.62)))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let authSummary = snapshot.authSummary {
                Text(authSummary)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.68))
                    .frame(width: 22, height: 22)
                Image(systemName: row.iconName ?? "chart.bar")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                Text(usedText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 92, alignment: .leading)

            UsageMeter(percent: clampedPercent ?? 0, color: isStale ? .secondary : barColor)
                .frame(height: 5)

            Text(row.percent.map { "\(Int($0.rounded()))%" } ?? row.value)
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
    }
}

private struct UsageMeter: View {
    let percent: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let width = max(percent > 0 ? 8 : 0, proxy.size.width * min(max(percent, 0), 100) / 100)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(nsColor: .separatorColor).opacity(0.36))
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
