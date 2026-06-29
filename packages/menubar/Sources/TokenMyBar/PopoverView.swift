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

    private let popoverWidth: CGFloat = 480
    private let cornerRadius: CGFloat = 22

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
                .overlay(Color(nsColor: .separatorColor).opacity(1.0))
            content
        }
        .frame(width: popoverWidth, height: contentHeight)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.22), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 18, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.red)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.red.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("TokenMyBar")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Updated \(updatedText)")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 0) {
                HeaderButton(
                    systemName: "arrow.clockwise",
                    isLoading: actions.isRefreshing,
                    accessibilityLabel: actions.isRefreshing ? "Refreshing" : "Refresh",
                    action: actions.onRefresh
                )
                .keyboardShortcut("r", modifiers: .command)

                HeaderButton(
                    systemName: "gearshape",
                    accessibilityLabel: "Settings",
                    action: actions.onSettings
                )
                .keyboardShortcut(",", modifiers: .command)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .frame(height: 68)
    }

    @ViewBuilder
    private var content: some View {
        if activeSnapshots.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "tray")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("No active vendors")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("Enable a vendor in Settings or refresh usage.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                ForEach(activeSnapshots, id: \.id) { snapshot in
                    VendorSection(snapshot: snapshot)
                    if snapshot.id != activeSnapshots.last?.id {
                        Divider()
                            .overlay(Color(nsColor: .separatorColor).opacity(1.0))
                    }
                }
            }
            .padding(.bottom, 10)
        }
    }
}

private struct HeaderButton: View {
    let systemName: String
    var isLoading = false
    let accessibilityLabel: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlAccentColor).opacity(isHovered ? 0.10 : 0))

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.82)
                } else {
                    Image(systemName: systemName)
                        .font(.system(size: 14, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 40, height: 40)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(accessibilityLabel)
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
        VStack(alignment: .leading, spacing: 0) {
            headerRow
                .padding(.bottom, 16)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(rows, id: \.id) { row in
                    UsageRowView(row: row, isStale: isStale)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(snapshot.displayName)
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: iconName)
                .font(.system(size: 15, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary)
                .frame(width: 24, height: 24)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(snapshot.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let plan = snapshot.planName {
                    Text(plan)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color(nsColor: .controlBackgroundColor).opacity(0.55)))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
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
        guard let percent = clampedPercent else { return Color(nsColor: .systemGray) }
        if percent >= 100 { return Color(nsColor: .systemRed) }
        if percent >= 70 { return Color(nsColor: .systemYellow) }
        return Color(nsColor: .systemGray)
    }

    private var resetText: String {
        row.detail ?? row.subtitle ?? " "
    }

    private var percentText: String {
        row.percent.map { "\(Int($0.rounded()))%" } ?? row.value
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Image(systemName: metricIconName)
                .font(.system(size: 14, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .padding(.trailing, 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(metricTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(resetText)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 100, alignment: .leading)

            Spacer(minLength: 8)

            UsageMeter(percent: clampedPercent ?? 0, color: isStale ? Color(nsColor: .systemGray) : barColor)
                .frame(width: 220, height: 8)

            Text(percentText)
                .font(.system(size: 13, weight: .regular).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
                .padding(.leading, 12)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private var metricTitle: String {
        switch row.key {
        case "session": "Rolling Usage"
        case "weekly": "Weekly Usage"
        case "monthly", "billing": "Monthly Usage"
        default: row.title
        }
    }

    private var metricIconName: String {
        switch row.key {
        case "session": "clock"
        case "weekly", "monthly", "billing": "calendar"
        default: row.iconName ?? "chart.bar"
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
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color(nsColor: .systemGray).opacity(0.30))
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(color)
                    .frame(width: width)
            }
            .accessibilityElement()
            .accessibilityLabel("Progress")
            .accessibilityValue("\(Int(percent))%")
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
