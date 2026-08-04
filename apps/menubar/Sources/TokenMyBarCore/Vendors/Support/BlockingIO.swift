import Foundation

/// Runs blocking IO — credential reads, SQLite, log scans, subprocesses — off
/// the Swift Concurrency cooperative pool.
///
/// `SecItemCopyMatching` on another app's Keychain item shows the macOS consent
/// dialog and does not return until it is answered — which, for a menu bar app
/// running for days, may be never. The cooperative pool is fixed at CPU-core
/// width and never grows, so blocking one of its threads per refresh starves it
/// until no vendor can refresh at all. Dispatch threads over-subscribe instead,
/// so a stuck prompt costs one idle thread rather than the whole pool.
///
/// Two lanes, split by whether the work can show a consent dialog. The
/// prompting lane is serial: a stuck prompt then costs exactly one thread
/// total instead of one per refresh tick, and reads queued behind it resolve
/// from Keychain's memo cache the moment the prompt is answered. Local work
/// gets its own concurrent lane so an unanswered prompt can never starve the
/// vendors — including the purely local ones — that need no consent at all.
enum BlockingIO {
    private static let promptingQueue = DispatchQueue(
        label: "app.coody.tokenmybar.blocking-io.prompting",
        qos: .utility
    )
    private static let localQueue = DispatchQueue(
        label: "app.coody.tokenmybar.blocking-io.local",
        qos: .utility,
        attributes: .concurrent
    )

    /// For reads that can raise a macOS consent dialog (Keychain, browser
    /// Safe Storage). Serial — see the type comment.
    ///
    /// Cancellation cannot interrupt a blocking Security call, so a cancelled
    /// caller leaves this suspended rather than resuming early.
    static func runPrompting<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            promptingQueue.async {
                continuation.resume(with: Result { try work() })
            }
        }
    }

    /// For blocking work that can never prompt: filesystem scans, SQLite,
    /// credential-file reads, subprocesses.
    static func run<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            localQueue.async {
                continuation.resume(with: Result { try work() })
            }
        }
    }
}
