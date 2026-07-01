# TokenMyBar Architecture

## Runtime Shape

TokenMyBar is a native macOS 14+ app built with Swift.

- `TokenMyBar`: AppKit menu bar host with SwiftUI popover/settings views.
- `TokenMyBarCore`: shared provider model, cache, refresh, formatting, and diagnostics contracts.
- `token-my-bar`: Swift CLI using `swift-argument-parser`, sharing `TokenMyBarCore`.

The app runtime must not depend on Node, npm, pnpm, Vite, or website tooling.

## Package Ownership

| Package | Role |
|---|---|
| `packages/menubar` | Native app, shared Swift core, Swift CLI, tests, release scripts |
| `packages/www` | Static website using React, Vite, Tailwind, shadcn-style components |
| Swift CLI | Lives inside `packages/menubar/Sources/TokenMyBarCLI`; no separate package |

## Provider Contract

Every provider maps source data into `ProviderSnapshot`.

Minimum supported fields:

- consumption value, currently `usedTokens` where possible
- `refreshedAt`
- `status`
- `primarySource`
- `confidence`

Optional fields:

- `usagePercent`
- `limitTokens`
- `resetAt`
- `windowName`

Provider-specific presentation rows live in `usageRows`. This follows the ai-usagebar lesson: providers expose genuinely different usage shapes, so rendering should preserve provider-specific rows instead of forcing everything into one flattened quota model.

Main UI shows primary source. Diagnostics can show full provenance.

## Combined Menu Bar Rule

Menu bar default is combined status.

Resolution order:

1. Configured `[ui] primary` vendor first, when it has known official `usagePercent`.
2. Remaining enabled vendors with known official `usagePercent`, joined as `X% | Y% | Z%`.
3. `--` when only local observed token counts are available.

Stale/error states keep last good value when available and dim the UI.

Local observed tokens are shown in the popover only. They are not shown as the menu bar headline because they are not the same as vendor quota percent.

## Auth Strategy

Auth uses existing vendor sessions directly from the Mac. TokenMyBar does not proxy vendor data through its own servers.

- Codex official usage uses OAuth from `~/.codex/auth.json` or `CODEX_HOME/auth.json`.
- Claude official usage uses OAuth from `~/.claude/.credentials.json`, then the
  `Claude Code-credentials` Keychain item. Reading that item triggers the macOS
  access prompt, which is the explicit user consent.
- OpenCode official usage uses the `opencode.ai` `auth` cookie: `TOKEN_MY_BAR_OPENCODE_COOKIE`
  first, then browser import (Chromium `v10` decryption + Firefox plaintext). A
  browser's Safe Storage Keychain key is only read when that browser holds a
  matching cookie.
- Local logs/SQLite remain fallback/cost-history sources and never become quota percentages unless vendor data exposes reset/limit semantics.
- External Keychain reads rely on the OS access prompt for consent; TokenMyBar never writes or repairs other apps' Keychain items.

## Cache

Path:

```text
~/Library/Application Support/token-my-bar/cache/snapshots.json
```

Rules:

- directory mode `0700`
- sensitive files `0600`
- atomic writes
- cross-process refresh lock at `snapshots.json.lock` using advisory `flock`
- cache TTL defaults to 120 seconds and is configurable
- no secrets in cache
- last good snapshot survives transient failures
- stale/error states should render last known value when safe

Config path:

```text
$XDG_CONFIG_HOME/token-my-bar/config.toml
~/.config/token-my-bar/config.toml
```

Example:

```toml
[ui]
primary = "codex"

[refresh]
ttl_seconds = 120
```

## Refresh

Current mechanism:

- configurable scheduled refresh (manual, 1m, 2m, 5m, 15m) via `AppSettings`
- manual refresh (popover button + menu, ⌘R)
- per-vendor enable/disable; disabled vendors are skipped
- shared `UsageRefresher` returns fresh cache within TTL before hitting APIs
- non-blocking cross-process refresh lock prevents multi-instance API stampedes
- last-good cache merge for stale/error states
- uniform per-refresh provider timeout (`UsageRefresher.providerTimeout`, default 20s)
- bounded automatic retry (1 retry) on transient HTTP/network failures (408/429/5xx) via `RemoteJSON.fetchData`

Menu bar app shell:

- left-click status item opens the SwiftUI popover (`.transient`, click-outside dismiss)
- right-click / control-click opens an `NSMenu`: Refresh, Launch at Login, Settings…, About, Quit
- Settings window (vendors, refresh interval, launch at login) via `SettingsWindowController`
- standard About panel via `NSApp.orderFrontStandardAboutPanel`
- launch at login via `SMAppService.mainApp`
- usage bars colored by `UsageSeverity` (normal/warning/critical)

Planned mechanism:

- per-provider tuned timeout and backoff policies (today's timeout and retry are uniform across all vendors)
- bounded provider-path watchers only where cheap and safe

No broad filesystem watching.

## Distribution

Direct and Homebrew builds:

- unsandboxed
- hardened runtime
- signed and notarized
- Sparkle for direct DMG updates is planned
- Homebrew users update through Homebrew

App Store is future separate sandboxed target.
