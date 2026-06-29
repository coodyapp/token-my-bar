---
summary: "Claude vendor: OAuth usage from api.anthropic.com plus local JSONL cost fallback."
read_when:
  - Debugging Claude usage parsing
  - Updating the Claude OAuth endpoint or credential resolution
  - Reviewing the local JSONL cost fallback
---

# Claude provider

Claude usage comes from the Claude Code OAuth session already stored on the Mac.
One official path plus a local cost fallback.

## Auth (credential resolution order)

1. `~/.claude/.credentials.json` file (Linux / older CLI installs), token at
   `claudeAiOauth.accessToken` or a flat `access_token`/`accessToken`.
2. macOS Keychain generic-password item `Claude Code-credentials` written by
   Claude Code. The token lives under the `claudeAiOauth` block; the unrelated
   `mcpOAuth` block is ignored.

Reading the Keychain item triggers the standard macOS access prompt — that
prompt is the explicit user consent. TokenMyBar never writes or repairs the
item, and requires the `user:profile` scope to call usage.

## Official usage (preferred)

- `GET https://api.anthropic.com/api/oauth/usage`.
- Headers: `Authorization: Bearer …`, `anthropic-beta: oauth-2025-04-20`.
- Response shape (per `ai-usagebar` reference):
  - Windows carry `utilization` (0–100) and `resets_at` (ISO-8601).
  - `five_hour` → "Session" row (drives the menu bar percent).
  - `seven_day` → "Weekly" row (all models).
  - `seven_day_sonnet` / `seven_day_opus` → model-specific rows.
  - `extra_usage` → "Extra usage" row: `monthly_limit` / `used_credits` in cents;
    ignored when `is_enabled` is false or the limit is zero.
- Plan label: `subscriptionType`, falling back to `rate_limit_tier`.

## Local cost fallback

When OAuth is unavailable, the provider falls back to local JSONL logs under
`~/.claude/projects` (and `$CLAUDE_CONFIG_DIR`). These are observed history only
and never become a quota percentage.

## Key files

- OAuth provider: `Sources/TokenMyBarCore/Providers/ClaudeCode/ClaudeOAuthUsageProvider.swift`
- Keychain reader: `Sources/TokenMyBarCore/Providers/Support/Keychain.swift`
- JSON parsing helpers: `Sources/TokenMyBarCore/Providers/Support/RemoteJSON.swift`
- Local fallback: `Sources/TokenMyBarCore/LocalJSONLUsageProvider.swift`

## Not implemented (future)

Claude web-cookie API, CLI `/usage` PTY automation, the Anthropic Admin API
dashboard, and multi-account switching are not implemented. Add them only as
clean-room work; do not import reference-project names, paths, caches, or config
files.
