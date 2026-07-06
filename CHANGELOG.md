# Changelog

All notable changes to TokenMyBar are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

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

[Unreleased]: https://github.com/coodyapp/token-my-bar/compare/v1.0.1...HEAD
[1.0.1]: https://github.com/coodyapp/token-my-bar/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/coodyapp/token-my-bar/releases/tag/v1.0.0
