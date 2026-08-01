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
- Response shape:
  - **`limits` array (preferred).** One entry per window, each naming its own
    `kind` (`session` / weekly), `percent` (0–100, percent used), `resets_at`,
    and — for a per-model cap — `scope.model.display_name`. This is the shape
    Claude Code's own usage screen reads, and the only place per-model caps such
    as "Fable" appear: the top-level `seven_day_*` keys report them as null. Rows
    are built straight from it, so a cap the account gains later is labelled
    without a code change (`<model> only`).
  - **Older keys (fallback), used only when `limits` is absent or empty.**
    Windows carry `utilization` (0–100) and `resets_at`. `five_hour` → "Session",
    `seven_day` → "Weekly", and any further `seven_day_*` key is enumerated into
    a model row rather than named in a hardcoded list.
  - `extra_usage` → "Extra usage" row: `monthly_limit` / `used_credits` in cents;
    ignored when `is_enabled` is false or the limit is zero. Appended in both
    shapes.
  - The menu bar percent still comes from `five_hour` (then `seven_day`, then the
    payload root) — not from the `limits` array.
- Plan label: the rate-limit tier wins over the subscription type, because the
  tier is what the on-screen percentages are a share of and the two disagree — a
  Max 5x account reports `subscriptionType: "max"` alongside
  `rateLimitTier: "default_claude_max_5x"`. The `default_claude_` prefix is
  stripped and the rest title-cased: `default_claude_max_5x` → "Max 5x". Keys are
  tried in order `rate_limit_tier`, `rateLimitTier`, `subscriptionType`,
  `subscription_type`, `plan` on the response, then the same tier-first rule on
  the stored credential payload.
- Reset timestamps: Anthropic sends microsecond precision
  (`…:00.084152+00:00`), which `ISO8601DateFormatter` rejects outright — it
  parses at most milliseconds. `RemoteJSON.parseISO8601` truncates the fraction
  and retries; without that every Claude row silently lost its reset time.
- A window the build cannot read a percentage from yields no row percent, and the
  snapshot goes to `error` ("Usage payload changed…") rather than reporting 0%.

## Local cost fallback

When OAuth is unavailable, the provider falls back to local JSONL logs under
`~/.claude/projects`. That path is not overridable — unlike Codex, there is no
`CLAUDE_CONFIG_DIR`-style env var. These are observed history only and never
become a quota percentage.

## Key files

- OAuth provider: `Sources/TokenMyBarCore/Vendors/ClaudeCode/ClaudeOAuthUsageProvider.swift`
- Keychain reader: `Sources/TokenMyBarCore/Vendors/Support/Keychain.swift`
- JSON parsing helpers: `Sources/TokenMyBarCore/Vendors/Support/RemoteJSON.swift`
- Local fallback: `Sources/TokenMyBarCore/LocalJSONLUsageProvider.swift`

## Not implemented (future)

Claude web-cookie API, CLI `/usage` PTY automation, the Anthropic Admin API
dashboard, and multi-account switching are not implemented. Add them only as
clean-room work; do not import reference-project names, paths, caches, or config
files.
