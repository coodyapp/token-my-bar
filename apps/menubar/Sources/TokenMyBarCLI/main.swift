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

    @Option(name: .long, help: "Vendor to print: codex, claude-code, or opencode.")
    var vendor: String?

    func run() async throws {
        let config = AppConfig.load()
        let refresher = UsageRefresher()
        let snapshots: [ProviderSnapshot]

        let cached = await refresher.cached()
        if refresh {
            snapshots = await refresher.refresh(ttl: 0)
        } else if !cached.isEmpty {
            snapshots = cached
        } else {
            snapshots = await refresher.refresh(ttl: config.refreshTTL)
        }

        let status = CombinedStatusFormatter.format(snapshots, primary: config.primaryVendor)

        if json {
            let snapshot = try selectSnapshot(from: snapshots, status: status, config: config)
            let data = try JSONEncoder.tokenMyBar.encode(snapshot.vendorReport())
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
                let extras = [row.subtitle, row.detail].compactMap { $0 }.joined(separator: " · ")
                let suffix = extras.isEmpty ? "" : " — \(extras)"
                print("  \(row.title): \(row.value)\(suffix)")
            }
        }
    }

    private func selectSnapshot(
        from snapshots: [ProviderSnapshot],
        status: CombinedStatus,
        config: AppConfig
    ) throws -> ProviderSnapshot {
        if let vendor {
            guard let providerID = AppConfig.vendor(from: vendor) else {
                throw ValidationError("Unknown vendor '\(vendor)'. Expected codex, claude-code, or opencode.")
            }
            guard let snapshot = snapshots.first(where: { $0.providerID == providerID }) else {
                throw ValidationError("No snapshot available for \(providerID.rawValue). Run with --refresh first.")
            }
            return snapshot
        }

        if let primary = config.primaryVendor,
           let snapshot = snapshots.first(where: { $0.providerID == primary }) {
            return snapshot
        }

        if let snapshot = status.snapshot ?? snapshots.first {
            return snapshot
        }

        throw ValidationError("No snapshots available. Run with --refresh first.")
    }
}
