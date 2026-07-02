# Installation

## DMG
1. Download `TokenMyBar-<version>.dmg` from the [latest release](https://github.com/coodyapp/token-my-bar/releases/latest).
2. Drag **TokenMyBar.app** to `/Applications` and launch. Menu bar only — no Dock icon.
3. Unsigned build: if Gatekeeper blocks it, right-click → **Open** → **Open**.

## Homebrew
```bash
brew tap coodyapp/token-my-bar https://github.com/coodyapp/token-my-bar
brew install --cask token-my-bar
```

## First run
No separate sign-in. TokenMyBar reads credentials your tools already stored: Claude Code (macOS Keychain — approve the consent prompt), Codex (`~/.codex/auth.json`), OpenCode (browser cookie import). Details: [docs/installation.md](https://github.com/coodyapp/token-my-bar/blob/main/docs/installation.md).
