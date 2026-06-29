# TokenMyBar

TokenMyBar does one thing perfectly: it turns your live AI token usage into a single, glanceable application right in your Mac's menu bar.

It is a native macOS menu bar app for OpenCode, OpenAI Codex, and Claude Code usage. The menu bar can show each vendor as a native icon plus percentage, percentage-only, icons-only, or a single summary value.

## What You See

- Native macOS popover with one material background, system icons, and system colors.
- Menu bar usage like `OpenCode icon 8% Codex icon 27% Claude icon 14%`.
- Vendor sections for OpenCode, Codex, and Claude with reset windows and usage meters.
- Settings for display mode, enabled vendors, summary calculation, and menu bar behavior.

## User Guide

See `docs/user-guide.md` for setup, settings, display modes, and troubleshooting.

## Packages

- `packages/menubar`: Swift macOS menu bar app, shared core, and Swift CLI.
- `packages/www`: React + Vite website.
- Swift CLI lives in `packages/menubar/Sources/TokenMyBarCLI`.

## Development

```bash
swift build --package-path packages/menubar
swift test --package-path packages/menubar
pnpm install
pnpm build:www
```

## Privacy

TokenMyBar reads existing local app sessions and cache data on your Mac. Snapshot cache does not store OAuth tokens, cookies, authorization headers, API keys, or passwords.
