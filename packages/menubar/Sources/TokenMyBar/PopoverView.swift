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

/// Native macOS menu-bar popover, modeled on Control Center / Wi-Fi / Sound menus.
/// Layout is driven entirely by spacing — no cards, no shadows beyond the system material.
struct PopoverView: View {
    let snapshots: [ProviderSnapshot]
    let actions: PopoverActions

    private enum Metrics {
        static let popoverWidth: CGFloat = 480
        static let cornerRadius: CGFloat = 24
        static let contentHorizontal: CGFloat = 20
    }

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
            HeaderView(
                updatedText: updatedText,
                isRefreshing: actions.isRefreshing,
                onRefresh: actions.onRefresh,
                onSettings: actions.onSettings
            )
            .padding(.horizontal, Metrics.contentHorizontal)

            Divider()

            content
        }
        .frame(width: Metrics.popoverWidth)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.22), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var content: some View {
        if activeSnapshots.isEmpty {
            EmptyStateView()
        } else {
            VStack(spacing: 0) {
                ForEach(Array(activeSnapshots.enumerated()), id: \.element.id) { index, snapshot in
                    if index > 0 { Divider() }
                    VendorSection(snapshot: snapshot)
                }
            }
        }
    }
}

// MARK: - Header

private struct HeaderView: View {
    let updatedText: String
    let isRefreshing: Bool
    let onRefresh: () -> Void
    let onSettings: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            // App logo — original red, never monochrome.
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 38, weight: .bold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.red)
                .frame(width: 52, height: 52)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("TokenMyBar")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.primary)

                Label("Updated \(updatedText)", systemImage: "clock")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                HeaderButton(
                    systemName: "arrow.clockwise",
                    isLoading: isRefreshing,
                    accessibilityLabel: isRefreshing ? "Refreshing" : "Refresh",
                    action: onRefresh
                )
                .keyboardShortcut("r", modifiers: .command)

                HeaderButton(
                    systemName: "gearshape",
                    accessibilityLabel: "Settings",
                    action: onSettings
                )
                .keyboardShortcut(",", modifiers: .command)
            }
        }
        .padding(.top, 20)
        .padding(.bottom, 16)
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
                Circle()
                    .fill(Color.primary.opacity(isHovered ? 0.12 : 0))
                Circle()
                    .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1)

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.85)
                } else {
                    Image(systemName: systemName)
                        .font(.system(size: 17, weight: .medium))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 38, height: 38)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(width: 48, height: 48)
        .onHover { isHovered = $0 }
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Vendor

private struct VendorSection: View {
    let snapshot: ProviderSnapshot

    private var isStale: Bool { snapshot.status == .stale || snapshot.status == .error }

    private var rows: [UsageRow] {
        if !snapshot.usageRows.isEmpty { return snapshot.usageRows }
        return [UsageRow(key: "status", title: snapshot.displayName, subtitle: snapshot.message, value: snapshot.status.label)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VendorHeader(snapshot: snapshot)
                .padding(.bottom, 26)

            VStack(alignment: .leading, spacing: 22) {
                ForEach(rows, id: \.id) { row in
                    UsageRowView(row: row, isStale: isStale)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(snapshot.displayName)
    }
}

private struct VendorHeader: View {
    let snapshot: ProviderSnapshot

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: iconName)
                .font(.system(size: 20, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.primary)
                .frame(width: 28, height: 28)

            Text(snapshot.displayName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            if let plan = snapshot.planName, !plan.isEmpty {
                PlanBadge(text: plan)
            }

            Spacer(minLength: 12)

            StatusBadge(status: snapshot.status)
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

/// Premium-tier capsule (e.g. "Plus"), shown only when the vendor reports a plan.
private struct PlanBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.secondary.opacity(0.18)))
            .accessibilityLabel("Plan \(text)")
    }
}

/// Trailing status capsule. Green "OK" for healthy vendors; yellow for stale data.
private struct StatusBadge: View {
    let status: ProviderStatus

    private var tint: Color {
        status == .ok ? .green : .yellow
    }

    private var iconName: String {
        status == .ok ? "checkmark.circle" : "clock"
    }

    private var label: String {
        status == .ok ? "OK" : "Stale"
    }

    var body: some View {
        Label(label, systemImage: iconName)
            .labelStyle(.titleAndIcon)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(tint.opacity(0.14)))
            .overlay(Capsule().stroke(tint.opacity(0.75), lineWidth: 1))
            .accessibilityLabel(label)
    }
}

// MARK: - Usage row

private struct UsageRowView: View {
    let row: UsageRow
    let isStale: Bool

    private var clampedPercent: Double? {
        row.percent.map { min(max($0, 0), 100) }
    }

    private var resetText: String {
        row.detail ?? row.subtitle ?? " "
    }

    private var percentText: String {
        row.percent.map { "\(Int($0.rounded()))%" } ?? row.value
    }

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: metricIconName)
                .font(.system(size: 18, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(metricTitle)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(resetText)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.leading, 16)

            Spacer(minLength: 12)

            ProgressBar(percent: clampedPercent ?? 0, isStale: isStale)
                .frame(width: 220, height: 10)

            Text(percentText)
                .font(.system(size: 17).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
                .padding(.leading, 18)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private var metricTitle: String {
        switch row.key {
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

// MARK: - Progress bar

/// Only the fill changes color — percentage text always stays monochrome.
/// Gray 0–69%, Yellow 70–99%, Red 100%.
private struct ProgressBar: View {
    let percent: Double
    let isStale: Bool

    private var fillColor: Color {
        if isStale { return Color(nsColor: .systemGray) }
        if percent >= 100 { return Color(nsColor: .systemRed) }
        if percent >= 70 { return Color(nsColor: .systemYellow) }
        return Color(nsColor: .systemGray)
    }

    var body: some View {
        GeometryReader { proxy in
            let fraction = min(max(percent, 0), 100) / 100
            let width = percent > 0 ? max(proxy.size.height, proxy.size.width * fraction) : 0
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(nsColor: .systemGray).opacity(0.30))
                Capsule()
                    .fill(fillColor)
                    .frame(width: width)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Usage")
        .accessibilityValue("\(Int(percent))%")
    }
}

// MARK: - Empty state

private struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("No active vendors")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
            Text("Enable a vendor in Settings or refresh usage.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 40)
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
