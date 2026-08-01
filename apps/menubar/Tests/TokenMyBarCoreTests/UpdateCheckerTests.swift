import Foundation
import Testing
@testable import TokenMyBarCore

@Test func updateVersionsCompareNumericallyNotAsText() {
    // "1.10.0" < "1.9.0" as text, which would hide every release past .9.
    #expect(UpdateChecker.isNewer("1.10.0", than: "1.9.0"))
    #expect(UpdateChecker.isNewer("v1.3.0", than: "1.2.0"))
    #expect(UpdateChecker.isNewer("2.0.0", than: "1.99.99"))
    #expect(!UpdateChecker.isNewer("1.2.0", than: "1.2.0"))
    #expect(!UpdateChecker.isNewer("1.1.0", than: "1.2.0"))
    // A pre-release of the version already installed is not an upgrade.
    #expect(!UpdateChecker.isNewer("1.2.0-beta.1", than: "1.2.0"))
    // Garbage must never be announced as a release.
    #expect(!UpdateChecker.isNewer("nightly", than: "1.2.0"))
}

@Test func updateCheckReportsOnlyNewerReleases() async {
    let checker = UpdateChecker(currentVersion: "1.2.0", store: .ephemeral(), fetchLatest: { "v1.3.0" })
    #expect(await checker.availableUpdate() == "v1.3.0")

    let current = UpdateChecker(currentVersion: "1.3.0", store: .ephemeral(), fetchLatest: { "v1.3.0" })
    #expect(await current.availableUpdate() == nil)
}

@Test func updateCheckAsksTheNetworkAtMostOncePerDay() async {
    // Opening the popover must never cost a request.
    let calls = Counter()
    let store = UpdateCheckStore.ephemeral()
    let checker = UpdateChecker(currentVersion: "1.2.0", store: store, fetchLatest: {
        await calls.increment()
        return "v1.3.0"
    })
    let start = Date(timeIntervalSince1970: 1_000_000)

    _ = await checker.availableUpdate(now: start)
    _ = await checker.availableUpdate(now: start.addingTimeInterval(3600))
    #expect(await calls.value == 1)
    // The remembered answer is still reported while the interval holds.
    #expect(await checker.availableUpdate(now: start.addingTimeInterval(3600)) == "v1.3.0")

    _ = await checker.availableUpdate(now: start.addingTimeInterval(25 * 3600))
    #expect(await calls.value == 2)
}

@Test func updateCheckStaysSilentWhenTheCheckFails() async {
    struct Offline: Error {}
    let checker = UpdateChecker(currentVersion: "1.2.0", store: .ephemeral(), fetchLatest: { throw Offline() })

    #expect(await checker.availableUpdate() == nil)
}

private actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}
