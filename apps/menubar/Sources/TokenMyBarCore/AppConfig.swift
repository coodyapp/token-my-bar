import Foundation

/// File-based configuration shared by the menu bar app and the CLI/widget.
///
/// Uses a minimal INI/TOML subset so a Waybar-style multi-instance setup can
/// pin a primary vendor and refresh cadence once, and so the OpenCode
/// overrides are reachable from the bundled app at all: an app launched by
/// Launch Services or as a login item inherits none of the user's shell
/// environment, so `TOKEN_MY_BAR_*` only ever reaches the CLI.
///
/// ```ini
/// [ui]
/// primary = codex
///
/// [refresh]
/// ttl_seconds = 120
///
/// [vendors]
/// disabled = claude-code, antigravity
///
/// [opencode]
/// cookie = "auth=…; other=…"
/// workspace_id = wrk_01ABC
/// db = ~/.local/share/opencode/opencode.db
/// ```
///
/// Environment variables win over the file (see `openCodeCookie`). A file
/// carrying `cookie` holds a live credential and should be `chmod 600`.
public struct AppConfig: Equatable, Sendable {
    public let primaryVendor: ProviderID?
    public let refreshTTL: TimeInterval
    /// `opencode.ai` session cookie, overriding browser import.
    ///
    /// A credential: it is never logged and never reaches a snapshot. The
    /// matching `TOKEN_MY_BAR_OPENCODE_COOKIE` takes precedence, because an env
    /// var is scoped to the one invocation that exports it while the file is
    /// permanent — a debugging session must not lose to a stale file.
    public let openCodeCookie: String?
    /// Workspace id to use instead of the `workspaces` server-function lookup,
    /// already validated by `OpenCodeCookieUsageProvider.isValidWorkspaceID`.
    public let openCodeWorkspaceID: String?
    /// Path to the local OpenCode SQLite database, `~` allowed. Also the app's
    /// only way to reach a non-default location, since `XDG_DATA_HOME` is a
    /// shell variable the bundle never sees.
    public let openCodeDatabasePath: String?
    /// Vendors the CLI must not fetch. The app keeps its own toggle in
    /// UserDefaults, which the CLI never reads — without this, a `--refresh`
    /// fetches vendors the user disabled, complete with their Keychain and
    /// browser-store consent prompts.
    public let disabledVendors: [ProviderID]

    public var enabledVendors: [ProviderID] {
        ProviderID.allCases.filter { !disabledVendors.contains($0) }
    }

    public static let defaultTTL: TimeInterval = 120

    public init(
        primaryVendor: ProviderID? = nil,
        refreshTTL: TimeInterval = AppConfig.defaultTTL,
        openCodeCookie: String? = nil,
        openCodeWorkspaceID: String? = nil,
        openCodeDatabasePath: String? = nil,
        disabledVendors: [ProviderID] = []
    ) {
        self.primaryVendor = primaryVendor
        self.refreshTTL = refreshTTL
        self.openCodeCookie = openCodeCookie
        self.openCodeWorkspaceID = openCodeWorkspaceID
        self.openCodeDatabasePath = openCodeDatabasePath
        self.disabledVendors = disabledVendors
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
        let config = AppConfig(contents: contents)
        // A world-readable file already exposed the cookie before this read, so
        // refusing it would protect nothing while breaking the only override a
        // user has when the vendor changes: warn and name the fix instead.
        if config.openCodeCookie != nil, !isOwnerOnly(url) {
            // Keep the message static: os_log redacts interpolated values, so a
            // path spliced in here would reach the user as "<private>".
            Log.app.notice("config file holds an [opencode] cookie but is readable by others; chmod 600 it")
        }
        return config
    }

    /// True when a file's mode grants no group or other access, i.e. 0600/0700.
    ///
    /// Resolves symlinks first: a dotfile manager (stow, chezmoi) links
    /// `~/.config` into a repo, and the link's own mode says nothing about the
    /// permissions of the file the cookie actually lives in.
    private static func isOwnerOnly(_ url: URL) -> Bool {
        let resolved = url.resolvingSymlinksInPath()
        guard let mode = try? FileManager.default.attributesOfItem(atPath: resolved.path)[.posixPermissions] as? NSNumber else {
            return true
        }
        return mode.int32Value & 0o077 == 0
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
            let raw = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            values["\(section).\(key)"] = AppConfig.value(from: raw)
        }

        self.primaryVendor = values["ui.primary"].flatMap(AppConfig.vendor(from:))
        if let ttl = values["refresh.ttl_seconds"].flatMap(Double.init), ttl >= 0 {
            self.refreshTTL = ttl
        } else {
            self.refreshTTL = AppConfig.defaultTTL
        }
        self.openCodeCookie = AppConfig.nonEmpty(values["opencode.cookie"])
        // The id is interpolated into a workspace URL path, so only a
        // well-formed one is kept; anything else is dropped and the provider
        // discovers the workspace over the network as if it were unset.
        self.openCodeWorkspaceID = AppConfig.nonEmpty(values["opencode.workspace_id"])
            .flatMap { OpenCodeCookieUsageProvider.isValidWorkspaceID($0) ? $0 : nil }
        self.openCodeDatabasePath = AppConfig.nonEmpty(values["opencode.db"])
        self.disabledVendors = AppConfig.nonEmpty(values["vendors.disabled"])
            .map { raw in
                raw.split(separator: ",").compactMap { token in
                    guard let id = AppConfig.vendor(from: String(token)) else {
                        // A silently dropped typo would re-trigger the very
                        // consent prompts this key exists to suppress. Static
                        // message: os_log redacts interpolated values.
                        Log.app.notice("[vendors] disabled contains an unrecognized vendor name; run `token-my-bar doctor` for the valid list")
                        return nil
                    }
                    return id
                }
            } ?? []
    }

    /// Unwraps one value: quoted takes it verbatim, unquoted ends at an inline
    /// `#`/`;` comment.
    ///
    /// A cookie header is `;`-separated, so quoting is the only way to write one.
    private static func value(from raw: String) -> String {
        if let quote = raw.first, quote == "\"" || quote == "'",
           let end = raw.dropFirst().firstIndex(of: quote) {
            return String(raw[raw.index(after: raw.startIndex)..<end])
        }
        var value = raw
        if let comment = value.firstIndex(where: { $0 == "#" || $0 == ";" }) {
            value = String(value[..<comment]).trimmingCharacters(in: .whitespaces)
        }
        return value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    /// Cache TTL to use for a scheduled refresh at `interval`.
    ///
    /// The configured TTL (120s by default) outlasts a shorter chosen interval,
    /// so every "Every 1 minute" tick would find fresh cache and skip fetching —
    /// the cadence the user picked has to win. Freshness is measured from when
    /// the cache was *written*, i.e. after a fetch that can take up to the
    /// provider timeout, so half the interval is the margin: it still absorbs a
    /// duplicate refresh within one tick, but a slow vendor — the case a user
    /// polling every minute most wants to watch — can no longer cost a whole
    /// tick and halve the effective cadence.
    public func timerTTL(interval: TimeInterval?) -> TimeInterval {
        guard let interval, interval > 0 else { return refreshTTL }
        return min(refreshTTL, interval / 2)
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
