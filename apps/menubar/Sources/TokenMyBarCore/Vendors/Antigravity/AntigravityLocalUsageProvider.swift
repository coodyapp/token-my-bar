import Foundation

/// Antigravity quota read from the language server the running IDE or CLI hosts.
///
/// This is the source Antigravity's own "Models & Quota" screen shows: models
/// are metered per *group* — all Gemini models share one allowance, Claude and
/// GPT share another — and the group's figure is what tells a user whether they
/// are about to be cut off.
///
/// It needs no Google token, so unlike the OAuth path it neither expires after
/// an hour nor depends on a permission the user's credentials do not carry. The
/// cost is that Antigravity has to be running; when it is not, the OAuth
/// provider answers instead.
public struct AntigravityLocalUsageProvider: ProviderClient {
    public let providerID: ProviderID = .antigravity
    private let portFinder: @Sendable () -> [Int]

    public init(portFinder: (@Sendable () -> [Int])? = nil) {
        self.portFinder = portFinder ?? { AntigravityLocalUsageProvider.listeningPorts() }
    }

    static let rpcPath = "/exa.language_server_pb.LanguageServerService/GetUserStatus"

    public func snapshot() async -> ProviderSnapshot {
        do {
            let status = try await userStatus()
            return Self.snapshot(from: status)
        } catch {
            return .failure(
                error,
                providerID: providerID,
                source: .localFile,
                authSummary: "Antigravity language server",
                missingMessage: "Antigravity is not running",
                failureMessage: "Antigravity language server did not answer"
            )
        }
    }

    private func userStatus() async throws -> [String: Any] {
        // Each server binds two ports and only one speaks plain HTTP; the other
        // answers TLS and is skipped rather than guessed at.
        for port in portFinder() {
            guard let url = URL(string: "http://127.0.0.1:\(port)\(Self.rpcPath)") else { continue }
            var request = URLRequest(url: url, timeoutInterval: 3)
            request.httpMethod = "POST"
            request.httpBody = Data("{}".utf8)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            guard let object = try? await RemoteJSON.fetchObject(request),
                  let status = object["userStatus"] as? [String: Any]
            else { continue }
            return status
        }
        throw AuthError.missingCredentials
    }

    static func snapshot(from status: [String: Any]) -> ProviderSnapshot {
        let rows = Self.rows(from: status)
        let plan = (status["planStatus"] as? [String: Any])
            .flatMap { $0["planInfo"] as? [String: Any] }
            .flatMap { $0["planName"] as? String }

        return ProviderSnapshot(
            providerID: .antigravity,
            status: rows.isEmpty ? .noData : .ok,
            usedTokens: nil,
            unit: .requests,
            usagePercent: rows.compactMap(\.percent).max(),
            windowName: .session,
            resetAt: rows.compactMap(\.resetAt).min(),
            refreshedAt: Date(),
            primarySource: .localFile,
            sources: [.localFile],
            confidence: .high,
            isEstimated: false,
            message: rows.isEmpty ? "Antigravity reported no model quota" : nil,
            authSummary: "Antigravity language server",
            planName: plan,
            usageRows: rows
        )
    }

    /// One row for the Gemini group.
    ///
    /// Models sharing an allowance report the identical `remainingFraction` and
    /// `resetTime`, which is what identifies a group; listing each model instead
    /// would repeat one number under a dozen names and read as a dozen separate
    /// pools. Claude and GPT models are metered separately and are not shown.
    static func rows(from status: [String: Any]) -> [UsageRow] {
        let configs = (status["cascadeModelConfigData"] as? [String: Any])
            .flatMap { $0["clientModelConfigs"] as? [[String: Any]] } ?? []

        var seen = Set<String>()
        var rows: [UsageRow] = []
        for config in configs {
            guard let modelID = config["modelId"] as? String,
                  modelID.lowercased().contains("gemini"),
                  let quota = config["quotaInfo"] as? [String: Any],
                  let remaining = RemoteJSON.double(quota, keys: ["remainingFraction", "remaining_fraction"]),
                  remaining.isFinite
            else { continue }
            let reset = RemoteJSON.resetDate(in: quota)
            let key = "\(remaining)|\(reset?.timeIntervalSince1970 ?? 0)"
            guard seen.insert(key).inserted else { continue }
            let used = min(max((1 - remaining) * 100, 0), 100)
            rows.append(UsageRow(
                key: "gemini-group",
                title: "Gemini models",
                subtitle: "Gemini Flash and Pro share this limit",
                value: "\(Int(used.rounded()))%",
                iconName: "sparkles",
                resetAt: reset,
                percent: used,
                unit: .requests
            ))
        }
        return rows
    }

    /// Ports the running Antigravity CLI or IDE is listening on.
    ///
    /// The server picks a port at start-up and does not record it anywhere on
    /// disk, so the open sockets of its own process are the only reliable place
    /// to look.
    static func listeningPorts() -> [Int] {
        guard let output = shell("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN"]) else { return [] }
        return ports(inLsofOutput: output)
    }

    static func ports(inLsofOutput output: String) -> [Int] {
        output
            .split(separator: "\n")
            .filter { line in
                let name = line.split(separator: " ").first.map(String.init) ?? ""
                return name == "agy" || name.lowercased().contains("antigravity")
            }
            .compactMap { line in
                // The address column sits before the trailing "(LISTEN)", so the
                // port is the last colon-separated number in the line, not the
                // last field.
                line.split(separator: " ")
                    .last { $0.contains(":") }
                    .flatMap { $0.split(separator: ":").last }
                    .flatMap { Int($0) }
            }
    }

    private static func shell(_ launchPath: String, _ arguments: [String]) -> String? {
        guard FileManager.default.isExecutableFile(atPath: launchPath) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
