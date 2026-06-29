import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public actor SnapshotStore {
    public let fileURL: URL
    private var refreshLock: FileLock?
    private var lockURL: URL { fileURL.appendingPathExtension("lock") }

    public init(fileURL: URL = SnapshotStore.defaultURL()) {
        self.fileURL = fileURL
    }

    public static func defaultURL() -> URL {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/token-my-bar/cache", isDirectory: true)
        return base.appendingPathComponent("snapshots.json")
    }

    public func load() throws -> [ProviderSnapshot] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder.tokenMyBar.decode([ProviderSnapshot].self, from: data)
    }

    /// Last write time of the cache file, used for TTL/freshness checks.
    public func modificationDate() -> Date? {
        try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date
    }

    /// True when the cache exists and is younger than `ttl`.
    public func isFresh(ttl: TimeInterval, now: Date = Date()) -> Bool {
        guard ttl > 0, let modified = modificationDate() else { return false }
        return now.timeIntervalSince(modified) < ttl
    }

    /// Returns cached snapshots only when still fresh, otherwise `nil`.
    public func loadIfFresh(ttl: TimeInterval, now: Date = Date()) -> [ProviderSnapshot]? {
        guard isFresh(ttl: ttl, now: now), let snapshots = try? load(), !snapshots.isEmpty else { return nil }
        return snapshots
    }

    public func save(_ snapshots: [ProviderSnapshot]) throws {
        try ensureDirectory()
        // Atomic temp-write + rename keeps concurrent readers consistent without
        // a write lock; cross-process single-flight is handled by the refresh lock.
        try writeAtomically(snapshots)
    }

    /// Attempts to acquire the cross-process refresh lock without blocking.
    ///
    /// Returns `true` only for the single instance that wins the lock; every
    /// other Waybar instance gets `false` and should reuse the cache instead of
    /// calling provider APIs. Must be paired with `endRefresh()`.
    public func tryBeginRefresh() -> Bool {
        guard refreshLock == nil else { return false }
        (try? ensureDirectory()) ?? ()
        guard let lock = FileLock(url: lockURL, exclusive: true, blocking: false) else { return false }
        refreshLock = lock
        return true
    }

    public func endRefresh() {
        refreshLock?.unlock()
        refreshLock = nil
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    private func writeAtomically(_ snapshots: [ProviderSnapshot]) throws {
        let directory = fileURL.deletingLastPathComponent()
        let data = try JSONEncoder.tokenMyBar.encode(snapshots)
        let tempURL = directory.appendingPathComponent(".snapshots.json.tmp")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        try data.write(to: tempURL, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tempURL.path)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tempURL)
        } else {
            try FileManager.default.moveItem(at: tempURL, to: fileURL)
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}

/// Thin wrapper over POSIX `flock` advisory locks.
final class FileLock {
    private let descriptor: Int32

    init?(url: URL, exclusive: Bool, blocking: Bool) {
        let fd = open(url.path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { return nil }
        var operation = exclusive ? LOCK_EX : LOCK_SH
        if !blocking { operation |= LOCK_NB }
        guard flock(fd, operation) == 0 else {
            close(fd)
            return nil
        }
        descriptor = fd
    }

    func unlock() {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }

    deinit { close(descriptor) }
}

extension JSONEncoder {
    static var tokenMyBar: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var tokenMyBar: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
