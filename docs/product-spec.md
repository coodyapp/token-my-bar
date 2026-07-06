# TokenMyBar Product Spec

> Note: This is the original product brief. See [architecture.md](architecture.md) for the current design.

## One-Line Description

TokenMyBar does one thing perfectly: it turns your live AI token usage into a single, glanceable application right in your Mac's menu bar.

## Scope

TokenMyBar is a macOS-only native menu bar app for three coding-agent vendors:

- OpenAI Codex
- Claude Code
- OpenCode

It is not a general AI billing dashboard. Official quota windows come from provider-owned auth sources. Local logs and SQLite history are fallback/cost-history sources only.

## Current Repository Shape

| Path | Role |
|---|---|
| `apps/menubar` | SwiftPM package for macOS app, shared core, CLI, tests |
| `apps/menubar/Sources/TokenMyBar` | AppKit/SwiftUI menu bar app |
| `apps/menubar/Sources/TokenMyBarCore` | Provider models, refresh/cache, parsers |
| `apps/menubar/Sources/TokenMyBarCLI` | Swift CLI binary `token-my-bar` |
| `apps/www` | React/Vite/Tailwind landing page |
| `docs/providers` | TokenMyBar provider specs |

No separate `apps/cli` package exists.

## Current CLI

- `token-my-bar status [--refresh]`
- `token-my-bar status --json [--vendor codex|claude-code|opencode]`
- `token-my-bar doctor`

JSON output uses one Waybar-compatible shape for every vendor: `text`, `tooltip`, `class`, `percentage`, `vendor`, `status`, and `windows`.

## Config

Path:

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

## Provider Strategy

### OpenAI Codex

- Primary: OAuth credentials from `~/.codex/auth.json` or `$CODEX_HOME/auth.json`.
- Official endpoint: `GET https://chatgpt.com/backend-api/wham/usage`.
- Fallback: local JSONL history from `~/.codex` or `TOKEN_MY_BAR_CODEX_HOME`.
- Local fallback never becomes official quota percent.

### Claude Code

- Primary: OAuth credentials from `~/.claude/.credentials.json`, then the
  `Claude Code-credentials` macOS Keychain item (`claudeAiOauth.accessToken`).
- Official endpoint: `GET https://api.anthropic.com/api/oauth/usage`.
- Fallback: local JSONL history from `~/.claude/projects`.
- Keychain reads use the OS access prompt for consent; TokenMyBar never writes.

### OpenCode

- Primary: `opencode.ai` `auth` cookie via `TOKEN_MY_BAR_OPENCODE_COOKIE`, then
  browser import (Chromium `v10` decryption + Firefox plaintext).
- Workspace IDs: `GET https://opencode.ai/_server?id=<workspacesFnID>`.
- Usage: `GET https://opencode.ai/workspace/<wrk_…>/go` (parsed from page JS).
- Workspace override: `TOKEN_MY_BAR_OPENCODE_WORKSPACE_ID`.
- Fallback: local SQLite history from `$XDG_DATA_HOME/opencode/opencode.db` or `~/.local/share/opencode/opencode.db`.

## UX Rules

- Menu bar shows highest known official usage percent: `TMB 42%`.
- Configured primary vendor wins when it has official usage percent.
- Menu bar shows `--` when only local observed tokens are available.
- Popover shows provider cards, source, status, reset/window rows, local fallback rows, and refresh action.
- Stale/error states can render last-good cached data when safe.
- No fake quota, fake reset, or fake cost numbers.

## Privacy Rules

- No TokenMyBar cloud account.
- No telemetry.
- No secrets in snapshot cache.
- Provider tokens/cookies stay on device.
- Diagnostics redact OAuth tokens, cookies, authorization headers, API keys, and emails where possible.
- Browser cookie import must be explicit and provider-scoped when implemented.

## Distribution Target

- macOS 14+ native app.
- Direct signed/notarized `.dmg` and Homebrew Cask are release goals.
- Roadmap: Developer ID signing + notarization once a paid Apple Developer
  account exists (release.yml/package.sh already support it via
  `DEVELOPER_ID_APP` + `AC_*` secrets). Until then releases are ad-hoc signed
  and users must clear quarantine (`--no-quarantine` or `xattr`).
- App Store is future work because sandbox constraints may limit provider auth/log access.

## Reference Inspiration

TokenMyBar should learn from `ai-usagebar` and `CodexBar` for provider behavior, quota semantics, parser fixtures, and macOS distribution patterns. Reference names, paths, caches, and config files must not leak into TokenMyBar docs or implementation unless intentionally adapted.
