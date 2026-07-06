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

@Test func resetSubtitleFormatsDaysHoursMinutes() {
    let now = Date(timeIntervalSince1970: 0)
    #expect(RemoteJSON.resetSubtitle(in: ["resetInSec": 4320], now: now) == "Resets in 1h 12m")
    #expect(RemoteJSON.resetSubtitle(in: ["resetInSec": 90_000], now: now) == "Resets in 1d 1h")
    #expect(RemoteJSON.resetSubtitle(in: ["resetInSec": 600], now: now) == "Resets in 10m")
    #expect(RemoteJSON.resetSubtitle(in: ["resetInSec": -100], now: now) == "Resets in 0m")
    #expect(RemoteJSON.resetSubtitle(in: [:], now: now) == nil)
}

@Test func percentReadsAliasesAndNormalizes() {
    #expect(RemoteJSON.percent(in: ["used_percent": 18]) == 18)
    #expect(RemoteJSON.percent(in: ["utilization": 47.0]) == 47)
    #expect(RemoteJSON.percent(in: ["usagePercent": "8"]) == 8)
    #expect(RemoteJSON.percent(in: ["percent": 0.39]) == 0.39)
    #expect(RemoteJSON.percent(in: ["other": 1]) == nil)
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
