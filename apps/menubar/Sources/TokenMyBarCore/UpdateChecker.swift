import Foundation

/// Tells a running copy that a newer release exists.
///
/// The app has no auto-update mechanism, so without this an install is frozen at
/// whatever version it was downloaded at — including versions since found to
/// report usage incorrectly. This is the smallest thing that fixes that: one
/// unauthenticated GET of the public releases API, at most once a day, sending
/// no identifier of any kind. It never downloads or installs anything; the user
/// decides what to do with the news.
public struct UpdateChecker: Sendable {
    /// The newest published release, or `nil` when the check fails or is skipped.
    public typealias LatestVersionSource = @Sendable () async throws -> String

    public static let releasesURL = "https://api.github.com/repos/coodyapp/token-my-bar/releases/latest"
    public static let releasesPage = "https://github.com/coodyapp/token-my-bar/releases/latest"
    static let checkInterval: TimeInterval = 24 * 60 * 60

    private let currentVersion: String
    private let fetchLatest: LatestVersionSource
    private let store: UpdateCheckStore

    public init(
        currentVersion: String,
        store: UpdateCheckStore = .userDefaults(),
        fetchLatest: LatestVersionSource? = nil
    ) {
        self.currentVersion = currentVersion
        self.store = store
        self.fetchLatest = fetchLatest ?? UpdateChecker.fetchLatestFromGitHub
    }

    /// The version to tell the user about, or `nil` when they are current.
    ///
    /// Answers from the last recorded result until a day has passed, so opening
    /// the popover never costs a network call.
    public func availableUpdate(now: Date = Date()) async -> String? {
        if let checkedAt = store.lastCheckedAt(), now.timeIntervalSince(checkedAt) < Self.checkInterval {
            return Self.newerVersion(store.lastSeenVersion(), than: currentVersion)
        }
        guard let latest = try? await fetchLatest() else { return nil }
        store.record(latest, now)
        return Self.newerVersion(latest, than: currentVersion)
    }

    static func newerVersion(_ candidate: String?, than current: String) -> String? {
        guard let candidate, isNewer(candidate, than: current) else { return nil }
        return candidate
    }

    /// Compares dotted versions numerically, so 1.10.0 beats 1.9.0 — which a
    /// string comparison gets backwards.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let left = components(of: candidate)
        let right = components(of: current)
        guard !left.isEmpty, !right.isEmpty else { return false }
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    private static func components(of version: String) -> [Int] {
        version
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            // Drop any pre-release suffix: "1.3.0-beta.1" compares as 1.3.0.
            .split(separator: "-").first
            .map { $0.split(separator: ".").compactMap { Int($0) } } ?? []
    }

    private static func fetchLatestFromGitHub() async throws -> String {
        var request = RemoteJSON.request(url: releasesURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let object = try await RemoteJSON.fetchObject(request)
        guard let tag = object["tag_name"] as? String else { throw AuthError.parseFailed }
        return tag
    }
}

/// Where the last check is remembered, so the interval survives a relaunch.
public struct UpdateCheckStore: Sendable {
    public let lastCheckedAt: @Sendable () -> Date?
    public let lastSeenVersion: @Sendable () -> String?
    public let record: @Sendable (_ version: String, _ at: Date) -> Void

    public init(
        lastCheckedAt: @escaping @Sendable () -> Date?,
        lastSeenVersion: @escaping @Sendable () -> String?,
        record: @escaping @Sendable (_ version: String, _ at: Date) -> Void
    ) {
        self.lastCheckedAt = lastCheckedAt
        self.lastSeenVersion = lastSeenVersion
        self.record = record
    }

    public static func userDefaults(suiteName: String? = nil) -> UpdateCheckStore {
        let checkedKey = "updateCheckedAt"
        let versionKey = "updateLatestVersion"
        // Resolved inside each closure rather than captured: UserDefaults is not
        // Sendable, and this store is read from whichever task the refresh runs on.
        let resolve: @Sendable () -> UserDefaults = {
            suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        }
        return UpdateCheckStore(
            lastCheckedAt: { resolve().object(forKey: checkedKey) as? Date },
            lastSeenVersion: { resolve().string(forKey: versionKey) },
            record: { version, at in
                let defaults = resolve()
                defaults.set(version, forKey: versionKey)
                defaults.set(at, forKey: checkedKey)
            }
        )
    }

    /// In-memory store for tests and for a build that should never persist.
    public static func ephemeral() -> UpdateCheckStore {
        final class Box: @unchecked Sendable {
            var checkedAt: Date?
            var version: String?
        }
        let box = Box()
        return UpdateCheckStore(
            lastCheckedAt: { box.checkedAt },
            lastSeenVersion: { box.version },
            record: { version, at in
                box.version = version
                box.checkedAt = at
            }
        )
    }
}
