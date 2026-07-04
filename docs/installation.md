# Installing TokenMyBar

TokenMyBar is a native macOS menu bar app. It requires **macOS 14 (Sonoma) or newer** on Apple Silicon.

## Option 1: DMG (recommended)

1. Download `TokenMyBar-<version>.dmg` from the [latest release](https://github.com/coodyapp/token-my-bar/releases/latest).
2. Open the DMG and drag **TokenMyBar.app** to `/Applications`.
3. Launch TokenMyBar. The app lives in the menu bar only (no Dock icon).

> **Unsigned build note:** current releases are not notarized. On first launch
> macOS Gatekeeper may block the app — for a fully unsigned binary, right-click
> → **Open** often has no bypass option. If so, strip the quarantine flag:
> `xattr -cr /Applications/TokenMyBar.app`, then open it (or allow it under
> **System Settings → Privacy & Security → Open Anyway**).

## Option 2: Homebrew

The cask lives in [coodyapp/homebrew-token-my-bar](https://github.com/coodyapp/homebrew-token-my-bar):

```bash
brew tap coodyapp/token-my-bar
brew install --cask token-my-bar
```

> **Tap trust:** recent Homebrew requires trusting third-party taps before
> loading casks from them. Rather than running `brew trust`, you can install
> with the check disabled for this one command:
> `HOMEBREW_NO_REQUIRE_TAP_TRUST=1 brew install --cask token-my-bar`.

## Option 3: Build from source

```bash
git clone https://github.com/coodyapp/token-my-bar.git
cd token-my-bar
apps/menubar/Scripts/package.sh
open apps/menubar/dist/TokenMyBar.app
```

See [development.md](development.md) for the full developer setup.

## First run

TokenMyBar reads usage from tools you already use — there is no separate sign-in:

- **Claude Code** — reads the OAuth credential Claude Code stored in the macOS
  Keychain. The first read triggers the standard macOS Keychain consent prompt;
  click **Allow** (or **Always Allow**).
- **OpenAI Codex** — reads `~/.codex/auth.json` written by the Codex CLI.
- **OpenCode** — imports the opencode.ai session cookie from your browser
  (Chrome/Chromium; decrypting its cookie store also prompts via Keychain), or
  set `TOKEN_MY_BAR_OPENCODE_COOKIE` yourself.

If a vendor shows **Sign in**, authenticate once in that vendor's own app and
refresh. See the [user guide](user-guide.md) for settings and troubleshooting,
and [privacy.md](privacy.md) for exactly what is read and stored.

## Uninstall

1. Quit TokenMyBar from the menu bar popover.
2. Delete `/Applications/TokenMyBar.app` (or `brew uninstall --cask token-my-bar`).
3. Optionally remove the snapshot cache: `rm -rf ~/Library/Application\ Support/TokenMyBar`.
