import Foundation
import Testing
@testable import TokenMyBarCore

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() { lock.lock(); value += 1; lock.unlock() }
    var current: Int { lock.lock(); defer { lock.unlock() }; return value }
}

@Test func blockingIOSerializesStuckPromptingReads() async throws {
    // A stuck consent prompt must cost exactly one thread. On a concurrent
    // queue every refresh tick stacked another blocked thread behind an
    // unanswered prompt; serialized, later reads queue until it resolves.
    let gate = DispatchSemaphore(value: 0)
    let secondRan = Counter()

    let first = Task {
        try await BlockingIO.runPrompting { gate.wait() }
    }
    // Let the first work item occupy the queue before enqueueing the second.
    try await Task.sleep(nanoseconds: 50_000_000)
    let second = Task {
        try await BlockingIO.runPrompting { secondRan.increment() }
    }
    try await Task.sleep(nanoseconds: 100_000_000)
    #expect(secondRan.current == 0)

    gate.signal()
    _ = try await first.value
    _ = try await second.value
    #expect(secondRan.current == 1)
}

@Test func blockingIOLocalLaneSurvivesAStuckPrompt() async throws {
    // Local scans (JSONL, SQLite, lsof, credential files) can never prompt,
    // so an unanswered consent dialog must not starve them: the vendors that
    // need no consent still have to refresh while a prompt sits open.
    let gate = DispatchSemaphore(value: 0)
    let localRan = Counter()

    let stuck = Task {
        try await BlockingIO.runPrompting { gate.wait() }
    }
    try await Task.sleep(nanoseconds: 50_000_000)
    let local = try await BlockingIO.run { localRan.increment(); return localRan.current }
    #expect(local == 1)

    gate.signal()
    _ = try await stuck.value
}
