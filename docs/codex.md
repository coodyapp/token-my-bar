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
  - Window fields: `used_percent` (0–100), `reset_after_seconds`, `reset_at`
    (epoch seconds). `RemoteJSON.resetDate` prefers the absolute `reset_at`
    because `reset_after_seconds` is the static window length (always 5h/7d),
    not the time actually left.
- Mapping:
  - `primary_window` drives the menu bar percent.
  - Each window is **titled by its declared length**, not by the field it arrived
    in: `limit_window_seconds` ≥ 20 days → "Monthly", ≥ 24h → "Weekly", otherwise
    "Session". The field name lies on some plans — a Plus account's
    `primary_window` is `limit_window_seconds: 604800`, i.e. the weekly limit its
    own `/status` screen shows, so it now reads "Weekly", not "Session".
  - Only when the vendor omits `limit_window_seconds` does the field name decide
    (`primary_window` → "Session", `secondary_window` → "Weekly").
  - `plan_type` → plan label.
- The endpoint reports percent **used**, already on the 0–100 scale every vendor
  uses here, so `CodexOAuthUsageProvider` passes it straight through
  `RemoteJSON.percent(in:)` — there is no inversion step. The chatgpt.com
  dashboard's "99% remaining" is its own inversion of `used_percent: 1`; treating
  the payload as "remaining" and flipping it was a real bug, so do not
  reintroduce one.

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
