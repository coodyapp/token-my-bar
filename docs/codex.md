---
summary: "Codex vendor: OAuth usage from chatgpt.com plus local JSONL cost fallback."
read_when:
  - Debugging Codex usage parsing
  - Updating the Codex OAuth endpoint or credential resolution
  - Reviewing the local JSONL cost fallback
---

# Codex provider

Codex usage comes from the OpenAI OAuth session that the Codex CLI already
stores on the Mac. There is one official path plus a local cost fallback.

## Auth

- Reads OAuth tokens from `~/.codex/auth.json` (or `$CODEX_HOME/auth.json`).
- Uses `access_token` for `Authorization: Bearer …`.
- Forwards `account_id` as `ChatGPT-Account-Id` when present.
- TokenMyBar does not refresh, rewrite, or copy `auth.json`.

## Official usage (preferred)

- `GET https://chatgpt.com/backend-api/wham/usage`.
- Response shape (per `ai-usagebar` reference):
  - `rate_limit.primary_window` → session/5-hour lane.
  - `rate_limit.secondary_window` → weekly lane.
  - Window fields: a percent value (0–100), `reset_after_seconds`, `reset_at`
    (epoch seconds).
- Mapping:
  - `primary_window` → "Session" row (drives the menu bar percent).
  - `secondary_window` → "Weekly" row.
  - `plan_type` → plan label.
- The endpoint reports percent **remaining** (starts at 100%, counts down).
  `CodexOAuthUsageProvider` inverts it to percent **used** via
  `RemoteJSON.percent(in:remaining: true)`, so Codex counts up 0→100 and colors
  its bar like the other vendors — 33% remaining renders as 67% used.

## Local cost fallback

When OAuth is unavailable, the provider falls back to local JSONL session logs
(`~/.codex/sessions/**/*.jsonl`, override `TOKEN_MY_BAR_CODEX_HOME`). Local token
counts are shown as observed history only and never become a quota percentage.

## Key files

- OAuth provider: `Sources/TokenMyBarCore/Vendors/Codex/CodexOAuthUsageProvider.swift`
- JSON parsing helpers: `Sources/TokenMyBarCore/Vendors/Support/RemoteJSON.swift`
- Local fallback: `Sources/TokenMyBarCore/LocalJSONLUsageProvider.swift`

## Not implemented (future)

Codex CLI RPC (`codex app-server`), `/status` PTY parsing, the OpenAI web
dashboard WebView, credits history, and multi-account profile homes are not
implemented. Add them only as clean-room work; do not import reference-project
names, paths, caches, or config files.
