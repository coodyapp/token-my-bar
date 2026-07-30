import Foundation

/// Runs a blocking credential read off the Swift Concurrency cooperative pool.
///
/// `SecItemCopyMatching` on another app's Keychain item shows the macOS consent
/// dialog and does not return until it is answered — which, for a menu bar app
/// running for days, may be never. The cooperative pool is fixed at CPU-core
/// width and never grows, so blocking one of its threads per refresh starves it
/// until no vendor can refresh at all. Dispatch threads over-subscribe instead,
/// so a stuck prompt costs one idle thread rather than the whole pool.
enum BlockingIO {
    private static let queue = DispatchQueue(
        label: "app.coody.tokenmybar.blocking-io",
        qos: .utility,
        attributes: .concurrent
    )

    /// Cancellation cannot interrupt a blocking Security call, so a cancelled
    /// caller leaves this suspended rather than resuming early.
    static func run<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try work() })
            }
        }
    }
}
