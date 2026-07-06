# Installing TokenMyBar

TokenMyBar is a native macOS menu bar app. It requires **macOS 14 (Sonoma) or newer** on Apple Silicon.

> **Unsigned build note:** releases are ad-hoc signed, not notarized (no Apple
> Developer ID yet). macOS Gatekeeper only checks *quarantined* apps, so the
> install script and the Homebrew cask below clear the quarantine flag for you
> and the app opens normally. Only a browser-downloaded DMG needs the manual
> step described in Option 3.

## Option 1: Install script (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/coodyapp/token-my-bar/main/install.sh | bash
```

Downloads the latest release DMG, verifies its SHA-256 checksum against the
published `.dmg.sha256`, installs **TokenMyBar.app** into `/Applications`, and
launches it. curl downloads carry no quarantine flag, so Gatekeeper does not
block the launch. Pass a version to pin one: `./install.sh 1.0.7`.

## Option 2: Homebrew

The cask lives in [coodyapp/homebrew-tap](https://github.com/coodyapp/homebrew-tap):

```bash
brew tap coodyapp/tap
brew install --cask token-my-bar
```

The cask removes the quarantine flag after install (postflight), so no
`--no-quarantine` env var or manual `xattr` is needed.

> **Tap trust:** recent Homebrew requires trusting third-party taps before
> loading casks from them. Rather than running `brew trust`, you can install
> with the check disabled for this one command:
> `HOMEBREW_NO_REQUIRE_TAP_TRUST=1 brew install --cask token-my-bar`.

## Option 3: DMG (manual)

1. Download `TokenMyBar-<version>.dmg` from the [latest release](https://github.com/coodyapp/token-my-bar/releases/latest).
2. Open the DMG and drag **TokenMyBar.app** to `/Applications`.
3. Strip the quarantine flag the browser download added (see the note above):
   `xattr -rd com.apple.quarantine /Applications/TokenMyBar.app` — or launch
   once and allow it under **System Settings → Privacy & Security → Open
   Anyway** (v1.0.7+; earlier releases show "damaged" with no bypass).
4. Launch TokenMyBar. The app lives in the menu bar only (no Dock icon).

## Option 4: Build from source

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
