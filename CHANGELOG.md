# Changelog

All notable changes to TokenMyBar are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.0.9] - 2026-07-30

### Fixed

- `token-my-bar status` and `--json` served whatever was in the cache forever:
  after the first run they never checked the cache's age, so a status bar polling
  the CLI could print weeks-old usage labelled "ok" — a 23-day-old reading with an
  expired reset countdown was reproduced — and `refresh.ttl_seconds` had no effect
  unless the cache file was deleted by hand.
- The on-disk cache could freeze at pre-failure numbers while the app displayed
  current ones, so the app and the CLI disagreed indefinitely. Display and
  persistence now come from a single decision per vendor, which is what let them
  drift apart in the first place: what is written is what is shown.
- Cached numbers re-shown after a failed refresh were stamped with the current
  time, so the popover said "Updated just now" and `updated_at` reported now for
  readings that could be days old. They now keep the time they were taken.
- A vendor whose refresh failed was recorded in the cache as healthy, so
  `token-my-bar --json` reported `"status": "ok"` with class `normal` — and the
  next app launch showed a green "OK" — for numbers that could not be refreshed.
  The cache now carries the same "stale" or "sign in" state the app shows.
- Uninstall docs pointed at `~/Library/Application Support/TokenMyBar`, a
  directory the app never creates, so `rm -rf` reported success while the real
  cache under `token-my-bar/` survived.
- Local Claude usage was counted about twice over. Claude Code writes one log
  record per assistant content block, each repeating the same message id and the
  same cumulative usage under a fresh `uuid`; deduping on the `uuid` let those
  repeats through. Measured on a real 198-file log directory, weekly local usage
  dropped from 2,830,836 to the true 1,357,574 tokens.
- A log line carrying a token count beyond `Int.max` (`1e300`, a 20-digit
  integer) crashed the app on launch and on every refresh until the file was
  deleted by hand. Token counts are now clamped and accumulated without
  trapping, and one unreadable or since-deleted log no longer aborts the whole
  scan and reports "Local logs not found".
- Vendors disabled in Settings no longer reappear in the menu bar and popover
  when a refresh reuses the shared cache (fresh-cache path, lock contention, and
  the startup cache read).
- Expired Claude authentication is no longer masked as merely "Stale" data — the
  popover says to sign in again while the last-known percent stays in the menu
  bar — and a failed refresh that still carries current local numbers is no
  longer replaced by older cached numbers.
- A vendor that cannot report a percent (expired auth, failed fetch) no longer
  disappears from the menu bar without a trace while other vendors keep showing
  numbers; it is flagged with a warning glyph instead.
- Local providers no longer emit rows of zeros when they find no usage, which
  had them counted as real data and displacing good cached numbers.
- The popover header read "Updated in 0 sec" — a time in the future — after
  every refresh; it now says "Updated just now".
- When a vendor has no usage to show, its reason ("Codex OAuth usage failed
  (HTTP 500)") was truncated mid-sentence next to an empty progress meter and a
  repeat of the vendor name. The message now gets the full width, and the
  meaningless meter is gone.
- Browser cookie import worked only while the browser was closed: a running
  browser keeps committed cookies in its SQLite write-ahead log, which the
  read-only copy of the main database file alone could not open.
- A blocking macOS Keychain consent prompt can no longer starve the concurrency
  pool and stall every vendor refresh.
- "Every 1 minute" refresh no longer degrades to a 2-3 minute cadence from the
  120s cache TTL, and refresh-lock races no longer overwrite newer cached data.
- "Hide labels when space is limited" now takes effect (its threshold could
  never be met), Settings reopens with the real Launch at Login state, and a
  first launch shows a loading state instead of "No active vendors".

### Changed

- Dev tooling: the popover snapshot renderer takes `TMB_SNAPSHOT_STATE=ok |
  degraded | loading | empty`, so the states users are most likely to be
  confused by can be eyeballed before a release instead of only the happy path.
- Website: the install command is the checksum-verifying install script (the
  advertised Homebrew tap command no longer worked), link previews use a real
  1200x630 social card, and the animated CTA and border trail respect
  `prefers-reduced-motion`.
- `install.sh` detects Apple Silicon from the hardware, so running it under
  Rosetta 2 no longer aborts on a supported Mac.
- Website deploys now run on manual dispatch and on `main` pushes that touch
  `apps/www`, instead of only on release tags.

## [1.0.8] - 2026-07-06

### Added

- `install.sh` one-liner installer: downloads the release DMG with curl (no
  quarantine flag, so no Gatekeeper block), verifies the published SHA-256,
  installs to `/Applications`, and launches the app.
- Styled DMG installer window ("Drag App to Applications" background with an
  Applications drop link) built with create-dmg; falls back to a plain DMG
  with an Applications symlink when create-dmg is unavailable.

### Changed

- Homebrew cask now strips the quarantine flag in a postflight, so plain
  `brew install --cask token-my-bar` opens without Gatekeeper prompts — no
  `--no-quarantine` env var or manual `xattr` needed.
- Installation docs reordered: install script first, Homebrew simplified,
  manual DMG with the quarantine step last; added a troubleshooting entry
  for launches stuck before startup after a Gatekeeper block.

## [1.0.7] - 2026-07-06

### Fixed

- Packaging: unsigned release builds now ad-hoc sign the entire app bundle.
  Previously only the executable carried the linker's ad-hoc signature, so
  Gatekeeper saw a broken bundle seal and reported quarantined installs
  (Homebrew or direct DMG download) as "damaged" ("Aplicativo está
  danificado") with no bypass. With a valid seal, macOS shows the standard
  unverified-developer flow with System Settings → Privacy & Security →
  Open Anyway.

### Changed

- Installation docs and Homebrew cask caveats now recommend installing with
  `--no-quarantine` or clearing the quarantine attribute with `xattr`,
  replacing the right-click → Open advice that does not work for these
  Gatekeeper verdicts.

## [1.0.6] - 2026-07-06

### Fixed

- Menu bar: local usage logs with fractional-second ISO8601 timestamps —
  the format Claude Code and Codex actually write (e.g. `…:20.906Z`) —
  failed to parse, so every recent entry was dropped from the session and
  weekly windows and the local-history fallback reported zero usage.
- Menu bar: refreshing a subset of providers (some disabled) overwrote the
  shared cache with only that subset, dropping the other vendors' last-good
  data that the CLI and other instances read; the persisted set now keeps
  cached-only vendors in a canonical order.
- Menu bar: a non-finite (NaN/Inf) usage percent from a malformed payload
  crashed the vendor report via `Int(percent.rounded())`; non-finite
  percents are now rejected at the source and the conversion is guarded.
- Menu bar: the "Selected Provider" summary showed `--` whenever no primary
  vendor was configured (the default) instead of falling back to the first
  vendor.
- Menu bar: the Claude OAuth file-credential path could return an unrelated
  `mcpOAuth` token; it now uses the same guarded extractor as the Keychain
  path, and Keychain lookups fetch each item by unique reference so
  duplicate service+account entries no longer collapse.
- Menu bar: browser cookie import matched look-alike domains via an
  unanchored `LIKE '%domain%'` and never filtered expired cookies; the host
  match is now anchored to the domain and its subdomains, expired cookies
  are dropped, and a superseded refresh no longer fires an extra network
  request after cancellation.
- Menu bar: compact counts render `1M` instead of `1000K` at the rounding
  boundary.
- Website: the install-command copy button handles clipboard failures
  (insecure context / denied permission) with an error toast instead of an
  unhandled rejection; the preview's refresh timers no longer accumulate
  timeout ids for the page's lifetime.

## [1.0.5] - 2026-07-04

### Changed

- Homebrew cask moved out of this repo to a dedicated
  [coodyapp/homebrew-tap](https://github.com/coodyapp/homebrew-tap) —
  `brew tap coodyapp/token-my-bar` → `brew tap coodyapp/tap`.

### Fixed

- Menu bar: session/weekly usage windowing used two different clocks,
  and records with no timestamp were counted into both windows forever.
- Menu bar: OpenCode cookie provider swallowed real auth/parse errors
  behind a generic "no data" message.
- Menu bar: popover row text could get squeezed instead of truncating;
  plan/status badges could wrap and break their pill shape; the vendor
  icon wasn't hidden from VoiceOver; Settings clipped at larger Dynamic
  Type; the popover no longer shows its default anchor arrow.
- Menu bar: vendor order in the CLI and popover was a network-race
  artifact (task-group completion order) instead of a fixed order.
- Menu bar/CLI: closed a TOCTOU permission window on the temp cookie DB
  copy and the browser-cookie-import temp file; CLI dropped a duplicate
  `JSONEncoder` config and a trailing-space bug in `--verbose` output.
- Website: build was broken (`vite.config.ts` read the now-removed
  `Casks/token-my-bar.rb` for its version string) — now reads
  `apps/www/package.json`'s own version instead.

## [1.0.4] - 2026-07-02

### Added

- Website: scroll-triggered fade-in (via `motion/react`, `whileInView`) on
  the install-terminal and menu-bar preview sections, disabled site-wide
  under `prefers-reduced-motion`. Terminal install commands now type in
  per-character via CSS `animation-delay` (no JS interval, so tests stay
  synchronous).

## [1.0.3] - 2026-07-02

### Fixed

- Website: removed a redundant zero-telemetry blurb from the hero CTA that
  duplicated messaging already present in the features section.

## [1.0.2] - 2026-07-02

### Added

- Website: favicon, canonical URL, and Open Graph/Twitter social preview
  meta tags — the site previously had none of the three.
- Website: `vitest` + Testing Library smoke tests for `Hero` and
  `MenubarPreview`, replacing the `test` script's former no-op (it only
  re-ran the TypeScript check, now moved to a separate `typecheck` script).

### Changed

- Website + README: refreshed copy to lead with real-time usage/reset/plan
  insight and call out the app's zero-telemetry, privacy-first design.

### Fixed

- Website: removed the light/dark theme toggle — the page's design is
  hardcoded dark-only, so switching theme flipped text colors without
  changing backgrounds, leaving unreadable dark-on-dark text. Also fixed
  a mobile bug where the hero heading's `line-height: 0` caused wrapped
  text to overlap.
- Website: added explicit width/height on the footer logo `<img>` to stop
  it causing layout shift while loading.
- Website: added `eslint-plugin-jsx-a11y` to the lint config.

### Removed

- Website: unused `chart-*`/`sidebar-*` CSS custom properties left over
  from the shadcn theme scaffold — never referenced by any component.

## [1.0.1] - 2026-07-02

### Changed

- Monorepo layout renamed from `packages/*` to `apps/*`.
- Website rebuilt: Tailwind CSS v4 (CSS-first theme), shadcn-style components,
  Geist Variable font, light/dark theme with no-flash init and a toggle,
  responsive layout, semantic landmarks/ARIA and reduced-motion support,
  Homebrew copy-to-clipboard install block.
- Website now deploys to Cloudflare Pages (`coody-tmb-www-prd-01`) from the
  tag-driven CD workflow.

## [1.0.0] - 2026-07-01

First stable release.

### Added

- Native macOS menu bar app showing live AI usage for **Claude Code**,
  **OpenAI Codex**, and **OpenCode** (icon+percent, percent-only, icons-only,
  and summary display modes).
- Plan badges per vendor (Claude "Pro"/"Max"/"Team" from stored credentials,
  Codex plan type, OpenCode "Go").
- Local-history fallback: when an official source is unavailable, usage is
  estimated from local JSONL logs / the OpenCode SQLite store and clearly
  marked as estimated.
- Snapshot cache with atomic writes, restrictive permissions, and stale-data
  labeling.
- Diagnostics CLI (`token-my-bar status|doctor`, `--json` Waybar payload).
- Settings: enabled vendors, refresh interval, display mode, summary
  calculation, launch at login.
- CI (build + test on macOS and Linux) and tag-driven release workflow that
  packages and publishes the DMG.
- Homebrew cask (`Casks/token-my-bar.rb`) and DMG distribution.

### Fixed

- Codex percentages were inverted (API `used_percent` is already percent
  used) and 1% could render as 100% due to a fraction-scaling heuristic;
  weekly reset showed the static window length instead of the real
  `reset_at` moment.
- Claude Code credentials were never found because macOS rejects batch
  Keychain reads that return secret data; reads are now enumerated
  per item (fixes permanent "unauthenticated" + wrong fallback numbers).
- `FileLock` double-closed its file descriptor, which could kill an unrelated
  descriptor that reused the number.
- Fallback snapshots preferred the failed official source's stale usage over
  fresh local data.
- Weekly local-log totals no longer undercount (JSONL truncation), vendor
  status ordering is deduplicated, and large token counts round correctly
  (K/M display).

### Security

- OAuth tokens/cookies are never logged or written to the snapshot cache;
  cache files are `0600`. Keychain access is read-only behind the standard
  macOS consent prompt. All SQLite access uses parameterized queries.

[Unreleased]: https://github.com/coodyapp/token-my-bar/compare/v1.0.9...HEAD
[1.0.9]: https://github.com/coodyapp/token-my-bar/compare/v1.0.8...v1.0.9
[1.0.8]: https://github.com/coodyapp/token-my-bar/compare/v1.0.7...v1.0.8
[1.0.7]: https://github.com/coodyapp/token-my-bar/compare/v1.0.6...v1.0.7
[1.0.6]: https://github.com/coodyapp/token-my-bar/compare/v1.0.5...v1.0.6
[1.0.5]: https://github.com/coodyapp/token-my-bar/compare/v1.0.4...v1.0.5
[1.0.4]: https://github.com/coodyapp/token-my-bar/compare/v1.0.3...v1.0.4
[1.0.3]: https://github.com/coodyapp/token-my-bar/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/coodyapp/token-my-bar/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/coodyapp/token-my-bar/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/coodyapp/token-my-bar/releases/tag/v1.0.0
