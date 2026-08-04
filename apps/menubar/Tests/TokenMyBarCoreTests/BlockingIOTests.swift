import Foundation
import Testing
@testable import TokenMyBarCore

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() { lock.lock(); value += 1; lock.unlock() }
    var current: Int { lock.lock(); defer { lock.unlock() }; return value }
}

@Test func blockingIOSerializesStuckReads() async throws {
    // A stuck consent prompt must cost exactly one thread. On a concurrent
    // queue every refresh tick stacked another blocked thread behind an
    // unanswered prompt; serialized, later reads queue until it resolves.
    let gate = DispatchSemaphore(value: 0)
    let secondRan = Counter()

    let first = Task {
        try await BlockingIO.run { gate.wait() }
    }
    // Let the first work item occupy the queue before enqueueing the second.
    try await Task.sleep(nanoseconds: 50_000_000)
    let second = Task {
        try await BlockingIO.run { secondRan.increment() }
    }
    try await Task.sleep(nanoseconds: 100_000_000)
    #expect(secondRan.current == 0)

    gate.signal()
    _ = try await first.value
    _ = try await second.value
    #expect(secondRan.current == 1)
}
