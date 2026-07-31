import Foundation
import Testing
@testable import TokenMyBarCore

@Test func normalizePercentClampsWithoutFractionScaling() {
    // Every vendor reports 0...100 (Codex used_percent: 1 means 1%, not 100%),
    // so small values must pass through unscaled.
    #expect(RemoteJSON.normalizePercent(0.46) == 0.46)
    #expect(RemoteJSON.normalizePercent(1.0) == 1)
    #expect(RemoteJSON.normalizePercent(42) == 42)
    #expect(RemoteJSON.normalizePercent(180) == 100)
    #expect(RemoteJSON.normalizePercent(-5) == 0)
}

@Test func resetDateReadsSecondsEpochAndISO() {
    let now = Date(timeIntervalSince1970: 1_000_000)

    let fromSeconds = RemoteJSON.resetDate(in: ["resetInSec": 3600], now: now)
    #expect(fromSeconds == now.addingTimeInterval(3600))

    let fromAfterSeconds = RemoteJSON.resetDate(in: ["reset_after_seconds": 120], now: now)
    #expect(fromAfterSeconds == now.addingTimeInterval(120))

    let fromEpoch = RemoteJSON.resetDate(in: ["reset_at": 1_779_597_324])
    #expect(fromEpoch == Date(timeIntervalSince1970: 1_779_597_324))

    let fromMillis = RemoteJSON.resetDate(in: ["reset_at": 1_779_597_324_000])
    #expect(fromMillis == Date(timeIntervalSince1970: 1_779_597_324))

    let fromISO = RemoteJSON.resetDate(in: ["resets_at": "2026-05-23T17:30:00Z"])
    #expect(fromISO == RemoteJSON.parseISO8601("2026-05-23T17:30:00Z"))

    #expect(RemoteJSON.resetDate(in: ["nope": 1]) == nil)
}

@Test func resetDatePrefersAbsoluteTimestampOverWindowSeconds() {
    // Codex sends both; reset_after_seconds is the static window length while
    // reset_at is the actual reset moment.
    let now = Date(timeIntervalSince1970: 1_000_000)
    let date = RemoteJSON.resetDate(
        in: ["reset_after_seconds": 604_800, "reset_at": 1_783_562_510],
        now: now
    )
    #expect(date == Date(timeIntervalSince1970: 1_783_562_510))
}

@Test func resetCountdownFormatsDaysHoursMinutes() {
    let now = Date(timeIntervalSince1970: 0)
    func countdown(_ seconds: TimeInterval) -> String {
        Format.resetCountdown(until: now.addingTimeInterval(seconds), now: now)
    }
    #expect(countdown(4320) == "Resets in 1h 12m")
    #expect(countdown(90_000) == "Resets in 1d 1h")
    #expect(countdown(600) == "Resets in 10m")
    #expect(countdown(-100) == "Resets in 0m")
}

@Test func rowStoresTheResetDateSoTheCountdownIsNeverFrozen() {
    // The countdown used to be rendered once at fetch time and persisted, so a
    // cached row still claimed "Resets in 26m" weeks later.
    let now = Date(timeIntervalSince1970: 1_000_000)
    let row = RemoteJSON.row(key: "session", title: "Session", object: ["used_percent": 20, "resetInSec": 3600], now: now)

    #expect(row.resetAt == now.addingTimeInterval(3600))
    #expect(row.resetText(now: now) == "Resets in 1h 0m")
    // An hour later the same row reports the time actually left, and once the
    // window has passed it reports nothing rather than a stale countdown.
    #expect(row.resetText(now: now.addingTimeInterval(1800)) == "Resets in 30m")
    #expect(row.resetText(now: now.addingTimeInterval(7200)) == nil)
}

@Test func rowReportsNoPercentRatherThanInventingZero() {
    // A window the vendor sent whose percent key this build does not know must
    // not read as "0% used" — that tells the user they have a full tank.
    let renamed = RemoteJSON.row(key: "weekly", title: "Weekly", object: ["utilization_pct": 88, "resetInSec": 60])

    #expect(renamed.percent == nil)
    #expect(renamed.value == "—")
    #expect(RemoteJSON.unreadableWindow(in: [renamed])?.title == "Weekly")
}

@Test func percentReadsAliasesAndNormalizes() {
    #expect(RemoteJSON.percent(in: ["used_percent": 18]) == 18)
    #expect(RemoteJSON.percent(in: ["utilization": 47.0]) == 47)
    #expect(RemoteJSON.percent(in: ["usagePercent": "8"]) == 8)
    #expect(RemoteJSON.percent(in: ["other": 1]) == nil)
    // A bare "percent" is direction-ambiguous — the vendor dashboards show
    // percent *remaining* — so it is not accepted at all.
    #expect(RemoteJSON.percent(in: ["percent": 0.39]) == nil)
}

@Test func windowsEnumeratesPerModelLimits() {
    // Claude grew a weekly "Fable" cap; a hardcoded sonnet/opus list drops it.
    let payload: [String: Any] = [
        "five_hour": ["utilization": 15],
        "seven_day": ["utilization": 22],
        "seven_day_fable": ["utilization": 0],
        "seven_day_opus": ["utilization": 3],
    ]

    let found = RemoteJSON.windows(in: payload, prefixes: ["seven_day_", "sevenDay"], excluding: ["seven_day", "sevenDay"])

    #expect(found.map(\.key) == ["seven_day_fable", "seven_day_opus"])
}

@Test func percentRejectsNonFiniteValues() {
    // A malformed payload can encode percent as "nan"/"inf" strings, which
    // Double(_:) parses to a non-finite value. These must be treated as "no
    // percent" (nil), never propagated — Int(nan.rounded()) would trap.
    #expect(RemoteJSON.percent(in: ["usagePercent": "nan"]) == nil)
    #expect(RemoteJSON.percent(in: ["utilization": "NaN"]) == nil)
    #expect(RemoteJSON.percent(in: ["percent": "inf"]) == nil)
    #expect(RemoteJSON.percent(in: ["used_percent": "-inf"]) == nil)
}
