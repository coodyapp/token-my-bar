# TokenMyBar

TokenMyBar is a native macOS menu bar app that gives you real-time insight into token usage, reset windows, and plan limits across Claude Code, OpenAI Codex, and OpenCode. Built with a privacy-first approach, it runs with zero telemetry.

## What You See

- Native macOS popover with one material background, system icons, and system colors.
- Menu bar usage like `OpenCode icon 8% Codex icon 27% Claude icon 14%`.
- Vendor sections for OpenCode, Codex, and Claude with reset windows and usage meters.
- Settings for display mode, enabled vendors, summary calculation, and menu bar behavior.

## Install

- **Install script** (recommended — verifies checksum, no Gatekeeper prompt):

  ```bash
  curl -fsSL https://raw.githubusercontent.com/coodyapp/token-my-bar/main/install.sh | bash
  ```

- **Homebrew**: `brew tap coodyapp/tap && brew install --cask token-my-bar`
- **DMG**: grab `TokenMyBar-<version>.dmg` from the [latest release](https://github.com/coodyapp/token-my-bar/releases/latest), drag to `/Applications`, then `xattr -rd com.apple.quarantine /Applications/TokenMyBar.app`.

Full instructions (Gatekeeper notes, first-run Keychain prompts, uninstall): [docs/installation.md](docs/installation.md).

## User Guide

See [docs/user-guide.md](docs/user-guide.md) for setup, settings, display modes, and troubleshooting. Changes per release: [CHANGELOG.md](CHANGELOG.md).

## Packages

- `apps/menubar`: Swift macOS menu bar app, shared core, and Swift CLI.
- `apps/www`: React + Vite website.
- Swift CLI lives in `apps/menubar/Sources/TokenMyBarCLI`.

## Development

```bash
swift build --package-path apps/menubar
swift test --package-path apps/menubar
pnpm install
pnpm build:www
```

Architecture, provider rules, and the release process live in [docs/development.md](docs/development.md).

## Privacy

TokenMyBar reads existing local app sessions and cache data on your Mac. Snapshot cache does not store OAuth tokens, cookies, authorization headers, API keys, or passwords.
