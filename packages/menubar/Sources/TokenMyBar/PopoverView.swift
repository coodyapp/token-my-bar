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
        .frame(width: 520, height: contentHeight)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .scaleEffect(didAppear ? 1 : 0.985, anchor: .topTrailing)
        .offset(x: didAppear ? 0 : 12)
        .opacity(didAppear ? 1 : 0)
        .animation(.spring(response: 0.32, dampingFraction: 0.9), value: didAppear)
        .onAppear { didAppear = true }
        .onDisappear { didAppear = false }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(.red.gradient)
                .frame(width: 48)

            VStack(alignment: .leading, spacing: 6) {
                Text("TokenMyBar")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.primary)
                Label("Updated \(updatedText)", systemImage: "clock")
                    .font(.system(size: 14, weight: .medium))
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
                            .font(.system(size: 22, weight: .medium))
                    }
                }
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color(nsColor: .controlBackgroundColor).opacity(0.58)))
                .overlay(Circle().stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1))
            }
            .buttonStyle(.plain)
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
                Image(systemName: "gearshape")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color(nsColor: .controlBackgroundColor).opacity(0.58)))
                    .overlay(Circle().stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More actions")
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 22)
    }

    @ViewBuilder
    private var content: some View {
        if activeSnapshots.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "tray")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("No active vendors")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)
                Text("Enable a vendor in Settings or refresh usage.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(activeSnapshots.enumerated()), id: \.element.id) { index, snapshot in
                    VendorSection(snapshot: snapshot)
                    if index < activeSnapshots.count - 1 {
                        Divider()
                            .overlay(Color(nsColor: .separatorColor).opacity(0.55))
                            .padding(.vertical, 12)
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
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
        VStack(alignment: .leading, spacing: 18) {
            headerRow
            VStack(alignment: .leading, spacing: 16) {
                ForEach(rows, id: \.id) { row in
                    UsageRowView(row: row, isStale: isStale)
                }
            }
        }
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: iconName)
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 40)
            HStack(alignment: .center, spacing: 8) {
                Text(snapshot.displayName)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.primary)
                if let plan = snapshot.planName {
                    Text(plan)
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color(nsColor: .controlBackgroundColor).opacity(0.62)))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let authSummary = snapshot.authSummary {
                Text(authSummary)
                    .font(.system(size: 11, weight: .semibold))
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
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.68))
                    .frame(width: 32, height: 32)
                Image(systemName: row.iconName ?? "chart.bar")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                Text(usedText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 130, alignment: .leading)

            UsageMeter(percent: clampedPercent ?? 0, color: isStale ? .secondary : barColor)
                .frame(height: 8)

            Text(row.percent.map { "\(Int($0.rounded()))%" } ?? row.value)
                .font(.system(size: 15, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
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
