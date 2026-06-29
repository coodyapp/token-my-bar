# TokenMyBar Privacy

TokenMyBar is local-first.

## Defaults

- No TokenMyBar cloud account.
- Zero telemetry.
- Manual cookie use only for providers that require it, currently OpenCode.
- No password storage.
- Provider API calls use existing provider credentials for enabled providers.
- App reads only known provider paths.

## Keychain

TokenMyBar may read app-owned Keychain items automatically.

External Keychain items from other apps or CLIs are never read silently. Claude Keychain bootstrap/repair requires explicit user action and explanation first.

## Provider Auth

- Codex: reads OAuth session from `~/.codex/auth.json` or `CODEX_HOME/auth.json`.
- Claude: reads OAuth session from `~/.claude/.credentials.json`; optional Keychain repair is user-triggered.
- OpenCode: reads `opencode.ai` session cookies from `TOKEN_MY_BAR_OPENCODE_COOKIE` today; explicit browser import UI is planned.
- Local cost/history scans read known provider log paths only.

## Full Disk Access

TokenMyBar does not ask for blanket Full Disk Access by default.

Flow:

1. Probe known provider paths.
2. If read fails, show provider-specific explanation.
3. User decides next action.

## Diagnostics Redaction

Diagnostics must redact:

- API keys
- OAuth tokens
- cookies
- authorization headers
- email addresses where possible
- local paths when exported for support

## Cache

Cache path:

```text
~/Library/Application Support/token-my-bar/cache/snapshots.json
```

Cache must not contain secrets.
