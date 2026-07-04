# Installation

## DMG
1. Download `TokenMyBar-<version>.dmg` from the [latest release](https://github.com/coodyapp/token-my-bar/releases/latest).
2. Drag **TokenMyBar.app** to `/Applications` and launch. Menu bar only — no Dock icon.
3. Unsigned build: if Gatekeeper blocks it with no "Open Anyway" option, run
   `xattr -cr /Applications/TokenMyBar.app`, then open it.

## Homebrew
```bash
brew tap coodyapp/tap
brew install --cask token-my-bar
```
Tap trust wall? Skip `brew trust` and install with the check disabled instead:
`HOMEBREW_NO_REQUIRE_TAP_TRUST=1 brew install --cask token-my-bar`.

## First run
No separate sign-in. TokenMyBar reads credentials your tools already stored: Claude Code (macOS Keychain — approve the consent prompt), Codex (`~/.codex/auth.json`), OpenCode (browser cookie import). Details: [docs/installation.md](https://github.com/coodyapp/token-my-bar/blob/main/docs/installation.md).
