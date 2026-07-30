# Full-project audit fixes (2026-07-29)

Source: 6-dimension ultracode audit workflow (32 agents, adversarial verification) →
26 confirmed findings, 21 unique after dedupe. All applied.
Baseline before: Swift 92 tests, www 5 tests. After: Swift 101, www 5.

## Swift Core (TDD)
- [x] 1. LocalJSONLUsageProvider — `Int(Double)` trapped on out-of-range JSON numbers → crash loop.
      Clamp via `maxTokenValue`/`clampTokens` + saturating `clampedSum`/`clampedAdd`.
- [x] 2. LocalJSONLUsageProvider.messageID — preferred per-line `uuid` over `message.id` → 2.07x
      token inflation (measured on real logs: weekly 2,830,836 → 1,357,574). Masking test fixture fixed.
- [x] 3. LocalJSONLUsageProvider — one unreadable .jsonl aborted the whole scan.
- [x] 4. UsageRefresher — TTL/lock/startup paths ignored the `enabled` filter → disabled vendors reappeared.
- [x] 5. UsageRefresher — merge baseline now read under the cross-process lock (stale-overwrite race).
- [x] 6. BlockingIO — Keychain/cookie reads off the cooperative pool; a stuck consent dialog no longer
      starves every refresh.
- [x] 7. SnapshotMerger — data-carrying failures keep their fresh data; expired auth stays `.unauthenticated`
      instead of flattening to `.stale`; disk cache still never overwritten by a failure.
- [x] 8. BrowserCookieImporter — copies `-wal`/`-shm` and opens the copy read-write; import was dead
      (SQLITE_CANTOPEN) while a browser was running.

## Menubar app UX
- [x] 9. AppConfig.timerTTL — "Every 1 minute" no longer degraded to 2-3 min by the 120s TTL.
- [x] 10. hideLabelsWhenSpaceLimited — threshold `> 3` was unreachable (3 vendors max) → `> 2`.
- [x] 11. SettingsModel.reload() on show() — reopened Settings showed stale Launch at Login.
- [x] 12. PopoverView — first run shows loading, not "No active vendors"; `.unauthenticated` tints as stale.

## www
- [x] 13. hero.tsx — install command pointed at a removed Homebrew tap → curl install script.
      Badge no longer advertises Homebrew (which now needs a tap-trust step) while showing curl.
- [x] 14. index.html — real 1200x630 dark social card (`public/og-image.png`), summary_large_image.
- [x] 15. border-trail.tsx — `offsetDistance` orbit now honors prefers-reduced-motion.
- [x] 16. hero.tsx — CTA conic spinner honors prefers-reduced-motion.
- [x] 17. App.tsx — page content moved inside the `<main>` landmark.

## Build / release / docs
- [x] 18. cd.yaml — deploy job was tag-gated; now runs on dispatch and www-touching main pushes
      (path filters don't apply to tag pushes — verified against GitHub docs).
- [x] 19. docs/development.md — release order bumps the www version before the deploy; Swift 6.0 prerequisite.
- [x] 20. CHANGELOG.md — link definitions for 1.0.2-1.0.8, Unreleased compares from v1.0.8.
- [x] 21. install.sh — Apple Silicon detected from hardware (`sysctl hw.optional.arm64`), not process arch.

## Verify
- [x] `swift build` clean, `swift test` 105/105 green (92 at baseline)
- [x] Red-green proven per fix: reverting each fix's logic turns its test red
      (dedupe 76 vs 38, enabled filter, merge unauth, WAL SQLITE_CANTOPEN)
- [x] Real-data check: scanned 198 real Claude log files, confirmed the 2.07x inflation and the fix
- [x] www: vitest 5/5, `tsc -b --noEmit` clean, eslint clean, `pnpm build:www` succeeds, og card 1200x630
- [x] `bash -n install.sh`, workflow YAML parses, CHANGELOG heading/link parity
- [x] Independent adversarial review of the Swift diff (3 lenses + judges)

## Round 2 — regressions found by adversarial review of round 1

The 3-lens review of my own Swift diff (13 agents) reported 10 problems; judges confirmed 6,
which dedupe to 4 real regressions I had introduced. All fixed, each red-green proven.

- [x] R1. SnapshotMerger's new "fresh data wins" guard counted all-zero placeholder rows as data.
      Local providers always emitted 4 rows (values "0") even at `.noData`, so a failed refresh
      displaced good cached numbers with "Session 0 / Weekly 0" — and made the new sign-in branch
      nearly dead code. Fixed at the source: no rows when the scan found nothing
      (`totalTokens > 0`), in both LocalJSONLUsageProvider and OpenCodeLocalUsageProvider.
      Weekly-only usage (quiet 5h window) still keeps its rows — covered by a test.
- [x] R2. CombinedStatusFormatter filtered to `.ok`/`.stale`, so preserving `.unauthenticated`
      dropped the vendor from the menu bar title and CLI status even when it carried a cached
      percent. PopoverView had been updated for that case; its two sibling consumers had not.
- [x] R3. A vendor with data but no percent still vanished from the bar → warning glyph appended
      when an unrepresented vendor is unauthenticated/errored. No invented numbers.
- [x] R4. timerTTL used `interval * 0.9`, which only budgeted the timer's jitter, not the fetch.
      Cache age is measured from the write at the *end* of a refresh, so any fetch over ~6s
      (an expired cookie burning its 15s timeout — exactly what 1-minute polling is for) still
      cost a whole tick. Now `interval / 2`; wake/manual refreshes force `ttl: 0` regardless.

Refuted by judges (no action): BlockingIO single-flighting (reported twice), vendor toggle
dropped during an in-flight refresh, hideLabels overriding collapse-to-summary.

## Round 3 — defects found by looking at the app

Static review can't see a layout. Rendered the popover with the DEBUG snapshot tool
(`TMB_SNAPSHOT=... swift run TokenMyBar`) and found two defects no audit lens caught, both
in the failure states users actually complain about:

- [x] V1. Header read **"Updated in 0 sec"** — a future time — after every refresh, because a
      snapshot stamped moments earlier (and cached copies restamped during the render itself)
      formats that way via RelativeDateTimeFormatter. Now "Updated just now" under 5s.
- [x] V2. A vendor with no usage rows rendered a synthesized row: the vendor name repeated from
      the header directly above it, the failure reason truncated mid-sentence ("Codex OAuth
      usage…") in a column squeezed by the meter, a truncated status word ("No d…"), and an
      empty progress bar implying 0% usage. The message now gets the full popover width and the
      meaningless meter is gone — the reason is the only useful thing left to say.
- [x] Extended the snapshot tool with `TMB_SNAPSHOT_STATE=ok|degraded|loading|empty` so these
      states stay eyeball-able before a release.
- [x] Confirmed by rendering: happy path unchanged, first-run shows "Loading usage…" (round-1
      fix), expired auth shows "Sign in" with its cached 42%/61% on gray bars (round-2 fix).
- [x] Exercised the real CLI end to end against the live cache: `doctor`, default status
      (`76% | 79% | 0%`), `--verbose`, and `--json` all correct.

## Round 4 — round-2 diff review + completeness critic

12 agents; 10 items reported, 4 confirmed by judges (2 were the same bug), 6 refuted.

- [x] C1 (HIGH, mine). `merge` and `snapshotsToSave` had drifted apart: round 2 taught `merge` to
      keep a data-carrying failure, but `snapshotsToSave` still wrote the older cache back. With
      expired auth plus local logs, the on-disk cache froze at pre-expiry numbers permanently —
      the app showed 1.2M while `token-my-bar --json` reported 42% with class "normal" and no
      re-auth signal, and every relaunch flashed the frozen value. Fixed the *class* of bug:
      one `SnapshotMerger.resolve` returns `{display, persist}` from a single decision per vendor,
      so the two can no longer disagree. Canonical vendor ordering also moved here from
      UsageRefresher (one place instead of two).
- [x] C2 (HIGH). The CLI never checked cache age: after the first run every invocation returned
      whatever was on disk, so `--json` served a 23-day-old snapshot as "ok" with a long-expired
      reset countdown, and `refresh.ttl_seconds` was dead config. Now routed through
      `refresh(ttl:)`, which returns a warm cache untouched (verified: 0.8s, no network) and
      refetches once it ages out.
- [x] C3 (LOW). docs/installation.md uninstall path was `Application Support/TokenMyBar`; the app
      writes `token-my-bar/`. `rm -rf` on the wrong path exits 0, so users believed they had
      deleted local usage history that was still there. A privacy-doc claim, so worth being exact.

Refuted (no action): zero-row snapshots blocking the cached percent, `--json` picking an
expired-auth vendor over a healthy one, permanent warning glyph on a default install,
pretty-printed JSON breaking Waybar, cached data restamped as fresh, adding-a-provider.md drift.

## Round 5 — round-4 diff review: clean, plus two honesty fixes it surfaced

The review of the merger refactor and CLI change confirmed **zero** defects (10 agents; every
reported item refuted as pre-existing and unchanged by the refactor). Judges did, however,
document two long-standing behaviors that are wrong for users regardless of who caused them —
and one of them was made more visible by the round-3 "Updated just now" fix:

- [x] H1. `staleCopy` restamped `refreshedAt` to now, so re-shown cached numbers claimed to be
      current: the popover header read "Updated just now" and the CLI's `updated_at` reported
      now for readings that could be days old. A re-presented reading now keeps the time it was
      actually taken.
- [x] H2. A failed vendor was recorded in the cache as `.ok`, so `token-my-bar --json` reported
      `"status": "ok"` / class `normal` (VendorUsageReport maps status straight to the Waybar
      class) and the next launch showed a green "OK" for numbers nobody could refresh. Since
      display and persistence are now one decision, persisting what we display fixes this and
      makes `resolve` simpler — the two lists differ only in the untouched vendors.
      The invariant that mattered ("a failure never destroys good numbers") still holds: the
      cached percent/rows survive; only the status stops lying.

Both red-green proven. Note this made the code shorter, not longer — the honest rule replaced
the special case.

- [x] H3. A dedicated verification of H2 (fixed-point stability, recovery, cold start, CLI
      contract, cache compatibility) found the one defect H2 introduced: because the cache can
      now hold `.unauthenticated`, a later unrelated failure — dropped network or a vendor 500,
      both `.error` — downgraded it to `.stale`, telling the user to wait for something that
      would never fix itself. `resolve` now keeps the sign-in state when either the fresh result
      or the cached fallback reports it. Red-green proven.

Verification evidence from that pass: 12 iterations of feeding `persist` back in reach an exact
fixed point after one round (numbers, rows, and timestamp bit-identical); one success fully
restores `.ok`; cold start shows the same menu bar title as before with correctly grayed bars;
`--json` stays coherent (`status: stale` / `class: warning`, true `updated_at`); and a compiled
v1.0.8 binary still decodes the new cache format (the stored schema and every `ProviderStatus`
case predate v1.0.0).

## Review

Product-facing outcome: the numbers TokenMyBar shows were wrong (roughly 2x too high) whenever the
local-log fallback was in play, the app could crash-loop on a single corrupt log line, OpenCode cookie
import silently did nothing while a browser was open, and disabling a vendor didn't reliably hide it.
Those were the four defects worth the most to a real user; all are fixed with tests that fail without
the fix.

Lessons captured:
- Reviewing my own diff with independent adversarial lenses paid for itself: four of my twelve
  fixes carried regressions, and the merger fix in particular was self-defeating (its own new
  sign-in message was unreachable). Fixing a display-selection rule means checking every consumer
  of that data — popover, menu bar title, and CLI all read the same snapshots.
- Two functions that must agree will eventually disagree. `merge`/`snapshotsToSave` drifted apart
  twice across these rounds; collapsing them into one `resolve` returning both answers removed the
  failure mode rather than the instance. Prefer that over a third patch.
- Look at the running product, not only the code: rendering the popover's degraded state found two
  defects (a future-tense timestamp, unreadable error text) that four review rounds over the same
  files did not, and running the real CLI found it serving 23-day-old numbers as current.
- A test fixture can hide the bug it names. `localJSONLScannerReadsClaudeShapeAndDedupesMessageID`
  reused the same `uuid` on both lines, so it passed while the dedupe it tested was broken.
  Fixtures must use realistic shapes (distinct uuids, shared message id).
- Verify a fix against real data when the input is real-world logs — the synthetic test proved the
  logic, the 198-file scan proved the magnitude.
- Never trust a scripted revert/restore of source files without re-grepping the marker afterwards:
  a backgrounded revert script overwrote a restore and three "failing fix" runs were really testing
  unfixed code.
