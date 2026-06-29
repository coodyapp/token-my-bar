import Foundation

/// Uniform per-vendor usage payload.
///
/// Every vendor module emits this identical JSON shape so external consumers
/// (Waybar `custom` modules, scripts, other bars) can render any vendor with
/// one template. Field names follow the Waybar `return-type: json` convention
/// (`text`, `tooltip`, `class`, `percentage`).
public struct VendorUsageReport: Codable, Equatable, Sendable {
    public struct Window: Codable, Equatable, Sendable {
        public let key: String
        public let title: String
        public let percent: Double?
        public let value: String
        public let detail: String?

        public init(key: String, title: String, percent: Double?, value: String, detail: String?) {
            self.key = key
            self.title = title
            self.percent = percent
            self.value = value
            self.detail = detail
        }
    }

    public let vendor: String
    public let name: String
    public let plan: String?
    public let status: String
    public let text: String
    public let tooltip: String
    public let percentage: Int?
    public let cssClass: String
    public let updatedAt: Date
    public let windows: [Window]

    private enum CodingKeys: String, CodingKey {
        case vendor, name, plan, status, text, tooltip, percentage
        case cssClass = "class"
        case updatedAt = "updated_at"
        case windows
    }

    public init(
        vendor: String,
        name: String,
        plan: String?,
        status: String,
        text: String,
        tooltip: String,
        percentage: Int?,
        cssClass: String,
        updatedAt: Date,
        windows: [Window]
    ) {
        self.vendor = vendor
        self.name = name
        self.plan = plan
        self.status = status
        self.text = text
        self.tooltip = tooltip
        self.percentage = percentage
        self.cssClass = cssClass
        self.updatedAt = updatedAt
        self.windows = windows
    }
}

public extension ProviderSnapshot {
    /// Projects this snapshot into the uniform vendor JSON shape.
    func vendorReport() -> VendorUsageReport {
        let percentInt = usagePercent.map { Int($0.rounded()) }
        let text = percentInt.map { "\(displayName) \($0)%" } ?? "\(displayName) --"

        let windows = usageRows.map { row in
            VendorUsageReport.Window(
                key: row.key,
                title: row.title,
                percent: row.percent,
                value: row.value,
                detail: row.detail ?? row.subtitle
            )
        }

        let tooltipLines = [displayName + (planName.map { " (\($0))" } ?? "")]
            + usageRows.map { row in
                let extra = [row.subtitle, row.detail].compactMap { $0 }.joined(separator: " · ")
                return extra.isEmpty ? "\(row.title): \(row.value)" : "\(row.title): \(row.value) — \(extra)"
            }

        return VendorUsageReport(
            vendor: providerID.rawValue,
            name: displayName,
            plan: planName,
            status: status.rawValue,
            text: text,
            tooltip: tooltipLines.joined(separator: "\n"),
            percentage: percentInt,
            cssClass: VendorUsageReport.cssClass(for: status, percent: usagePercent),
            updatedAt: refreshedAt,
            windows: windows
        )
    }
}

private extension VendorUsageReport {
    static func cssClass(for status: ProviderStatus, percent: Double?) -> String {
        switch status {
        case .ok, .stale:
            switch UsageSeverity(percent: percent) {
            case .normal: "normal"
            case .warning: "warning"
            case .critical: "critical"
            }
        case .loading: "loading"
        case .noData: "no-data"
        case .unauthenticated: "unauthenticated"
        case .error: "error"
        }
    }
}
