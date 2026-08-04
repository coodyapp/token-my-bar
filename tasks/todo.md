# Dual-review remediation plan (2026-08-02)

Source: two external reviews, every claim adversarially verified against code by 12
independent agents. Of 44 claims: 29 confirmed, 10 partially confirmed (details
corrected below), 5 effectively refuted. Workflow per fix: failing test first where
testable, then the minimal fix, one focused commit each.

## Review corrections (claims we are NOT fixing as stated)

- R1-H1 "keychain continuation leak" — mechanism refuted. SnapshotRace's single
  continuation always resumes (loser's resolve is a guarded no-op,
  UsageRefresher.swift:157-160). Real kernel: BlockingIO's `.concurrent` queue lets
  stuck consent reads stack one blocked thread per refresh tick. Downgraded HIGH→LOW;
  fixed in P3-1 by making the queue serial.
- R1 "DMG notarized but app not stapled" — fabricated. Nothing in the release
  pipeline notarizes (release.yml passes no credentials; package.sh skips).
- R1-M5a Intel support — Apple Silicon-only is documented (README.md:17) and
  installer-enforced (install.sh:26-30). Product decision, not a defect.
- R1-M5b NSHighResolutionCapable — key is ignored for 10.15+-SDK builds; no blur.
- R2-12 shadcn misalignment — tokens are consumed (hero.tsx); preview's raw hex is
  deliberate 1pt=1px macOS fidelity. No change.
- R2-10d fixed Settings window / SwiftUI Settings scene — AppKit lifecycle is a
  design choice; migration is not a minimal fix. No change.
- R1-LOW prefersReducedMotion — re-evaluated every cycle, CSS/MotionConfig already
  reactive. No change.

## P0 — crash & launch correctness

- [x] 1. Delegate lifetime (R1-H2, CONFIRMED high): TokenMyBarApp.swift:13-17 —
  `withExtendedLifetime(delegate) { app.run() }`. Verify: build -c release, launch,
  status item appears.
- [x] 2. Claude NaN trap (R2-2, CONFIRMED, crash reproduced): ClaudeOAuthUsageProvider
  `doubleValue` (~:176-183) — require `isFinite` on Double and parsed-String branches.
  Tests first: `used_credits: "nan"` → "0%" row not a trap; `"inf"/"inf"`; negative;
  huge-finite.
- [x] 3. Unguarded private KVC (R2-10b): TokenMyBarApp.swift:57 — wrap
  `shouldHideAnchor` in `responds(to: NSSelectorFromString("setShouldHideAnchor:"))`;
  degrade to visible anchor, never launch-crash.

## P1 — wrong data/status shown to users

- [x] 4. Antigravity fallback composition (R2-1): FallbackProviderTests — new red test:
  primary .unauthenticated(.localFile) + fallback .ok(.oauth, isEstimated:false) must
  return the fallback verbatim. Fix in FallbackProvider.snapshot() (ProviderClient.swift
  ~:44): `if local.status == .ok && !local.isEstimated { return local }`. Also fix test
  stub to set `isEstimated: true` for local-history stubs (matches real providers) and
  keep all 7 existing tests green.
- [x] 5. Local providers `.noData` beside real data (R2-8a/b): key status on the same
  predicate as rows — `usage.totalTokens > 0 ? .ok : .noData` in
  LocalJSONLUsageProvider.swift:89 and OpenCodeLocalUsageProvider.swift:78, three-way
  message ("No tokens in the current 5h window" when session empty but data exists).
  Flip pinned test `localJSONLSnapshotKeepsRowsWhenOnlyTheSessionWindowIsEmpty` to .ok
  (red today); add mirror OpenCode test. Also closes the third silent-vanish route via
  FallbackProvider inheriting .noData.
- [x] 6. Vendor vanishes with no glyph (R1-M6, corrected): headline drop for elapsed
  windows is deliberate — widen the attention predicate instead. Extract
  `needsAttention` into TokenMyBarCore; true for unshown vendors with
  .unauthenticated/.error OR (.ok/.stale AND has a percent). Use from
  TokenMyBarApp.swift:280 and :325. Red test: .ok snapshot, all rows elapsed, one other
  vendor shown → needsAttention == true.
- [x] 7. OpenCode schema drift eaten (R2-5): OpenCodeCookieUsageProvider loop — keep
  last parsed non-ok snapshot; prefer a .error ("Usage payload changed…") over generic
  noData. Extract pure `resolve(parsed:lastError:)`; tests for window-with-only-
  resetInSec and loop precedence.
- [x] 8. CLI contract (R1-M3 corrected + disabled-vendors, both real): (a) reserve
  ValidationError for unknown vendor; data-unavailable exits 1 (plain Error), and with
  --json emit a valid stub payload so Waybar always parses; (b) add
  `[vendors] disabled =` key to AppConfig, pass `enabled:` from main.swift:51 (refresh
  honors it already, tested); (c) derive --vendor help + unknown-vendor error from
  `ProviderID.allCases` so antigravity can never be omitted again. Move selection logic
  into TokenMyBarCore for unit tests (CLI target has zero coverage today).

## P2 — truth: copy, docs, CI gates

- [x] 9. Settings privacy copy (R2-3): SettingsWindow.swift:209 → "TokenMyBar reads
  usage from your existing vendor sessions on this Mac. Requests go only to your
  vendors, plus a daily anonymous GitHub update check — never to a TokenMyBar server."
- [x] 10. Antigravity docs sweep (R1-M7/R2-14, 8 confirmed spots): architecture.md:75-82,
  antigravity.md:122-128 (self-contradiction), adding-a-provider.md, product-spec.md:90,
  privacy.md:42, installation.md, README.md:12, user-guide.md:39 — all to local-first
  language-server RPC with OAuth fallback, one grouped "Gemini models" row. Delete
  phantom "Use original colored icons" bullet (user-guide.md:59). Pinning test: assert
  the .antigravity registry entry is a FallbackProvider.
- [x] 11. CI gates (R2-13/13b/low): `prettier --write` the 5 failing www files; www
  `test` script → `tsc -b --pretty false && vitest run` (makes CONTRIBUTING.md:55 true);
  add eslint + `prettier --check` steps to ci.yml www job; add `permissions: contents:
  read` + `timeout-minutes` to ci.yml (and timeout to release.yml); align Node 24 /
  checkout@v5 with cd.yaml; add .github/dependabot.yml (github-actions + npm).

## P3 — hardening & polish (one batch, still test-first)

- [x] 12. BlockingIO serial queue (real kernel of R1-H1): drop `.concurrent` from
  BlockingIO.swift:12-16 so a stuck consent prompt costs exactly one thread and queued
  reads hit Keychain's memo cache. Test: semaphore-blocked first item, assert second
  doesn't start until signaled.
- [x] 13. Route blocking work through BlockingIO (R2-7): Antigravity lsof `portFinder`,
  OpenCodeLocalUsageProvider.readUsage, LocalJSONLUsageProvider.scanUsage, credential
  file reads. No behavior change; existing tests stay green.
- [x] 14. Settings honesty (R1-M4/R2-9): remove `DisplayMode.custom` (raw "custom"
  already decodes to .iconPercentage — add test); extract pure
  `effectiveDisplayMode(...)` into Core with tests, check collapse-to-summary BEFORE
  hide-labels; rename "Monochrome icons" label to match behavior (colors text only);
  delete dead `settings.launchAtLogin` key + its writes; setEnabled returns Bool and
  failure shows a caption instead of a silent toggle revert.
- [x] 15. Swift misc: PopoverView.swift:468 a11y value uses `.rounded()` via one shared
  percent formatter in Core (+test 69.6→"70%"); live status-item accessibility title
  from statusSegments() (spoken-string builder in Core, +test); UpdateChecker Box gets
  a lock; strict version parsing — reject partially-numeric tags ("1.foo.9" → [],
  +red test); shared `clampedSum` helper for OpenCodeLocalUsage.totalTokens and
  cache-reasoning row (+Int.max test).
- [x] 16. www fixes: figcaption alpha 0.45→0.55 (5.45:1, passes AA) at
  menubar-preview.tsx:458; `aria-valuenow={target}` at :234; add VITE_TMB_VERSION
  define to vitest config (+red test asserting /^v\d/ in hero); hero.tsx:79 span→div;
  bar `w-[150px] min-w-14 shrink` + `min-w-0` label column, verify at 320/375px.
- [x] 17. install.sh: normalize `version="${version#v}"` so `v1.0.7` works (+bash test).

## Deferred — user decision required

- Developer ID signing + notarization (R2-4): package.sh already supports it; needs a
  paid Apple Developer account and CI secrets (DEVELOPER_ID_APP, AC_*). Current ad-hoc
  posture is documented and intentional. Decide separately.
- Localization catalog, SwiftUI Settings migration, semantic fonts: scope decisions,
  not defects.

## Review (2026-08-03)

All 17 items landed on `fix/dual-review-remediation`, released as v1.6.0.
Every fix followed red-green: 155 -> 176 Swift tests, 5 -> 6 www tests, and
the attention-predicate fix was additionally verified by reverting it (4
failures) per the project rule. Full www gates (tsc, eslint, prettier,
vitest, vite build) and shellcheck pass; the release build launches.

Notable deviations from the plan:
- R1's "keychain continuation leak" fix landed as the one-line serial
  BlockingIO queue (item 12), exactly as the verification predicted — no
  SnapshotRace change was needed because the claimed leak mechanism was
  refuted.
- FallbackProvider also gained `resetAt: official ?? local` — a secondary
  provenance defect the verification agents found beyond the reviews.
- Developer ID signing/notarization remains deferred (needs an Apple
  Developer account and CI secrets; package.sh already supports it).

## Lessons

- Green tests enshrined two of the bugs (the fallback stub modeled local
  history as isEstimated=false; the noData-beside-weekly-rows test asserted
  the contradiction). Verifying reviews against code before fixing caught
  both reviews' fabrications (notarized-but-not-stapled; the continuation
  leak mechanism) before they could misdirect the work.
