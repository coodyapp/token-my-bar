#if os(macOS)
import SwiftUI
import TokenMyBarCore

struct PopoverActions {
    var isRefreshing: Bool
    /// Set when a newer release exists, so an install that can never update
    /// itself at least says so.
    var availableUpdate: String?
    var onRefresh: () -> Void
    var onSettings: () -> Void
    var onAbout: () -> Void
    var onQuit: () -> Void
}

/// Native macOS menu-bar popover, modeled on Control Center / Wi-Fi / Sound menus.
/// Compact native typography, tight vertical rhythm, layout driven by spacing — no cards.
struct PopoverView: View {
    let snapshots: [ProviderSnapshot]
    let actions: PopoverActions

    private enum Metrics {
        static let popoverWidth: CGFloat = 380
        static let cornerRadius: CGFloat = 14
        static let contentHorizontal: CGFloat = 14
    }

    /// Vendors worth a row: usage vendors plus any in an error / sign-in /
    /// no-data state, so the user sees *why* a vendor is missing instead of a
    /// blank empty state. Only purely-loading (no content) vendors are hidden.
    private var displaySnapshots: [ProviderSnapshot] {
        snapshots.filter { $0.status != .loading }
    }

    private var updatedText: String {
        guard let date = snapshots.map(\.refreshedAt).max() else { return "never" }
        // A snapshot stamped moments ago — every fresh refresh, and every cached
        // copy restamped during this very render — formats as "in 0 sec", which
        // reads as the future.
        guard Date().timeIntervalSince(date) >= 5 else { return "just now" }
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

            if let update = actions.availableUpdate {
                Divider()
                UpdateBanner(version: update)
            }
        }
        .frame(width: Metrics.popoverWidth)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.20), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var content: some View {
        if displaySnapshots.isEmpty {
            // On a fresh install there is no cache to show, so "no vendors" would
            // send a first-run user to Settings for a problem that doesn't exist.
            if snapshots.isEmpty, !actions.isRefreshing {
                EmptyStateView()
            } else {
                LoadingStateView()
            }
        } else {
            VStack(spacing: 0) {
                ForEach(Array(displaySnapshots.enumerated()), id: \.element.id) { index, snapshot in
                    if index > 0 { Divider() }
                    VendorSection(snapshot: snapshot)
                }
            }
        }
    }
}

// MARK: - Update

/// Shown only when a newer release exists. The app cannot update itself, so the
/// most it can honestly do is say so and open the page.
private struct UpdateBanner: View {
    let version: String
    @State private var isHovered = false

    var body: some View {
        Link(destination: URL(string: UpdateChecker.releasesPage)!) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.tint)
                Text("Update available — \(version)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .background(Color.primary.opacity(isHovered ? 0.06 : 0))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel("Update available, version \(version). Opens the releases page.")
    }
}

// MARK: - Header

private struct HeaderView: View {
    let updatedText: String
    let isRefreshing: Bool
    let onRefresh: () -> Void
    let onSettings: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // App logo — original red, never monochrome.
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 20, weight: .bold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.red)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("TokenMyBar")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)

                Label("Updated \(updatedText)", systemImage: "clock")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            HStack(spacing: 2) {
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
        .padding(.top, 12)
        .padding(.bottom, 10)
    }
}

/// Borderless icon button with hover highlight — the Control Center / toolbar idiom.
private struct HeaderButton: View {
    let systemName: String
    var isLoading = false
    let accessibilityLabel: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(isHovered ? 0.10 : 0))

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: systemName)
                        .font(.system(size: 13, weight: .medium))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 26, height: 26)
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Vendor

private struct VendorSection: View {
    let snapshot: ProviderSnapshot

    /// Expired auth also shows cached numbers, so its bars must not read as live.
    private var isStale: Bool {
        snapshot.status == .stale || snapshot.status == .error || snapshot.status == .unauthenticated
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VendorHeader(snapshot: snapshot)
                .padding(.bottom, snapshot.usageRows.isEmpty ? 6 : 10)

            if snapshot.usageRows.isEmpty {
                // Why this vendor has nothing to show is the only useful thing
                // left to say, so give it the full width instead of squeezing it
                // into a usage row beside an empty meter.
                Text(snapshot.message ?? snapshot.status.label)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(snapshot.usageRows, id: \.id) { row in
                        UsageRowView(row: row, isStale: isStale)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(snapshot.displayName)
    }
}

private struct VendorHeader: View {
    let snapshot: ProviderSnapshot

    /// Only for readings that are not current — a live vendor's age is noise.
    private var ageText: String? {
        guard snapshot.status != .ok, snapshot.status != .loading else { return nil }
        guard !snapshot.usageRows.isEmpty || snapshot.usagePercent != nil else { return nil }
        return Format.compactAge(since: snapshot.refreshedAt)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: snapshot.providerID.iconName)
                .font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.primary)
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)

            Text(snapshot.displayName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            if let plan = snapshot.planName, !plan.isEmpty {
                PlanBadge(text: plan)
            }

            // The header's "Updated" line reports the newest vendor, so a vendor
            // whose own reading is old needs to say so next to its numbers.
            if let age = ageText {
                Text(age)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            StatusBadge(status: snapshot.status)
        }
    }
}

/// Premium-tier capsule (e.g. "Plus"), shown only when the vendor reports a plan.
private struct PlanBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.secondary.opacity(0.18)))
            .accessibilityLabel("Plan \(text)")
    }
}

/// Trailing status capsule. Color and glyph track the vendor's state so
/// errors, expired auth, and missing data read at a glance — not just OK/Stale.
private struct StatusBadge: View {
    let status: ProviderStatus

    private var tint: Color {
        switch status {
        case .ok: .green
        case .stale, .loading: .yellow
        case .unauthenticated: .orange
        case .error: .red
        case .noData: .secondary
        }
    }

    private var iconName: String {
        switch status {
        case .ok: "checkmark.circle"
        case .stale, .loading: "clock"
        case .unauthenticated: "person.crop.circle.badge.exclamationmark"
        case .error: "exclamationmark.triangle"
        case .noData: "questionmark.circle"
        }
    }

    var body: some View {
        Label(status.label, systemImage: iconName)
            .labelStyle(.titleAndIcon)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(Capsule().fill(tint.opacity(0.14)))
            .overlay(Capsule().stroke(tint.opacity(0.55), lineWidth: 1))
            .accessibilityLabel(status.label)
    }
}

// MARK: - Usage row

private struct UsageRowView: View {
    let row: UsageRow
    let isStale: Bool

    /// A window whose reset has already passed describes a period that is over.
    /// Its number is not the current load, so it is withheld rather than shown
    /// next to windows that are live.
    private var hasElapsed: Bool {
        guard let resetAt = row.resetAt else { return false }
        return resetAt <= Date()
    }

    private var clampedPercent: Double? {
        guard !hasElapsed else { return nil }
        return row.percent.map { min(max($0, 0), 100) }
    }

    private var resetText: String {
        if hasElapsed { return "Window ended" }
        return row.resetText() ?? row.detail ?? row.subtitle ?? " "
    }

    private var percentText: String {
        guard !hasElapsed else { return "—" }
        return row.percent.map { "\(Int($0.rounded()))%" } ?? row.value
    }

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: metricIconName)
                .font(.system(size: 13, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(metricTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(resetText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.leading, 9)

            Spacer(minLength: 12)

            ProgressBar(percent: clampedPercent ?? 0, isStale: isStale)
                .frame(width: 150, height: 6)

            Text(percentText)
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .trailing)
                .padding(.leading, 10)
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

// MARK: - Loading state

private struct LoadingStateView: View {
    var body: some View {
        VStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Loading usage…")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 28)
    }
}

// MARK: - Empty state

private struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("No active vendors")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
            Text("Enable a vendor in Settings or refresh usage.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 28)
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
