# Changelog

All notable changes to TokenMyBar are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

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
