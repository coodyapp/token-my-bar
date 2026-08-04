import ArgumentParser
import Foundation
import TokenMyBarCore

@main
@available(macOS 10.15, *)
struct TokenMyBarCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "token-my-bar",
        abstract: "TokenMyBar diagnostics and vendor tools.",
        subcommands: [Doctor.self, Status.self],
        defaultSubcommand: Status.self
    )
}

struct Doctor: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Check local TokenMyBar setup.")

    func run() async throws {
        let cacheURL = SnapshotStore.defaultURL()
        print("TokenMyBar doctor")
        print("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        print("cache: \(cacheURL.path)")
        print("vendors: \(ProviderID.allCases.map(\.rawValue).joined(separator: ", "))")
    }
}

struct Status: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Print current combined status.")

    @Flag(name: .long, help: "Refresh vendors before printing status.")
    var refresh = false

    @Flag(name: .shortAndLong, help: "Print per-vendor usage detail.")
    var verbose = false

    @Flag(name: .long, help: "Print a Waybar-compatible per-vendor JSON payload.")
    var json = false

    @Option(name: .long, help: "Vendor to print: \(ProviderID.allCases.map(\.rawValue).joined(separator: ", ")).")
    var vendor: String?

    func run() async throws {
        let config = AppConfig.load()
        let refresher = UsageRefresher()
        // Always go through refresh: it returns the cache untouched while it is
        // younger than the TTL, so honoring `refresh.ttl_seconds` costs nothing on
        // a warm cache. Reading the cache directly instead made every invocation
        // after the first serve whatever was on disk, forever — a status bar
        // polling this printed weeks-old numbers labelled "ok".
        // `[vendors] disabled` is honored here: the app's own toggle lives in
        // UserDefaults the CLI never reads, and fetching a disabled vendor can
        // raise its Keychain/browser-store consent prompts.
        let snapshots = await refresher.refresh(enabled: config.enabledVendors, ttl: refresh ? 0 : config.refreshTTL)

        let status = CombinedStatusFormatter.format(snapshots, primary: config.primaryVendor)

        if json {
            let report: VendorUsageReport
            switch SnapshotSelection.select(from: snapshots, vendor: vendor, primary: config.primaryVendor, combined: status.snapshot) {
            case .snapshot(let snapshot):
                report = snapshot.vendorReport()
            case .unknownVendor(let raw):
                throw ValidationError("Unknown vendor '\(raw)'. Expected \(ProviderID.allCases.map(\.rawValue).joined(separator: ", ")).")
            case .unavailable(let providerID):
                // A data condition, not a usage error: still emit the uniform
                // payload so a polling bar renders "--" instead of breaking.
                report = SnapshotSelection.placeholderReport(for: providerID)
            }
            let data = try JSONEncoder.tokenMyBar.encode(report)
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
            return
        }

        print(status.title)

        guard verbose else { return }
        for snapshot in snapshots {
            print("")
            let authSuffix = snapshot.authSummary.map { " \($0)" } ?? ""
            print("\(snapshot.displayName) [\(snapshot.status.rawValue)]\(authSuffix)")
            if let message = snapshot.message {
                print("  note: \(message)")
            }
            for row in snapshot.usageRows {
                // Countdowns are formatted at display time, so the CLI has to ask
                // for one the same way the popover does rather than printing a
                // `detail` string that no longer carries it.
                let extras = [row.subtitle, row.resetText() ?? row.detail]
                    .compactMap { $0 }
                    .joined(separator: " · ")
                let suffix = extras.isEmpty ? "" : " — \(extras)"
                print("  \(row.title): \(row.value)\(suffix)")
            }
        }
    }

}
