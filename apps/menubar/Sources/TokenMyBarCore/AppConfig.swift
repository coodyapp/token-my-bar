import Foundation

/// File-based configuration shared by the menu bar app and the CLI/widget.
///
/// Uses a minimal INI/TOML subset so a Waybar-style multi-instance setup can
/// pin a primary vendor and refresh cadence once:
///
/// ```ini
/// [ui]
/// primary = codex
///
/// [refresh]
/// ttl_seconds = 120
/// ```
public struct AppConfig: Equatable, Sendable {
    public let primaryVendor: ProviderID?
    public let refreshTTL: TimeInterval

    public static let defaultTTL: TimeInterval = 120

    public init(primaryVendor: ProviderID? = nil, refreshTTL: TimeInterval = AppConfig.defaultTTL) {
        self.primaryVendor = primaryVendor
        self.refreshTTL = refreshTTL
    }

    public static func defaultURL() -> URL {
        if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            return URL(fileURLWithPath: xdg, isDirectory: true)
                .appendingPathComponent("token-my-bar/config.toml")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/token-my-bar/config.toml")
    }

    /// Loads config from disk, returning defaults when the file is missing or empty.
    public static func load(from url: URL = AppConfig.defaultURL()) -> AppConfig {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return AppConfig()
        }
        return AppConfig(contents: contents)
    }

    /// Parses config from an in-memory INI/TOML string.
    public init(contents: String) {
        var section = ""
        var values: [String: String] = [:]

        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") { continue }

            if line.hasPrefix("["), line.hasSuffix("]") {
                section = line.dropFirst().dropLast().trimmingCharacters(in: .whitespaces).lowercased()
                continue
            }

            guard let separator = line.firstIndex(of: "=") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces).lowercased()
            var value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            if let comment = value.firstIndex(where: { $0 == "#" || $0 == ";" }) {
                value = String(value[..<comment]).trimmingCharacters(in: .whitespaces)
            }
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            values["\(section).\(key)"] = value
        }

        self.primaryVendor = values["ui.primary"].flatMap(AppConfig.vendor(from:))
        if let ttl = values["refresh.ttl_seconds"].flatMap(Double.init), ttl >= 0 {
            self.refreshTTL = ttl
        } else {
            self.refreshTTL = AppConfig.defaultTTL
        }
    }

    /// Maps user-friendly vendor aliases to a vendor ID.
    public static func vendor(from raw: String) -> ProviderID? {
        let normalized = raw.trimmingCharacters(in: .whitespaces).lowercased()
        return switch normalized {
        case "codex", "openai", "openai-codex": .codex
        case "claude", "claude-code", "anthropic": .claudeCode
        case "opencode", "open-code": .opencode
        default: ProviderID(rawValue: normalized)
        }
    }
}
