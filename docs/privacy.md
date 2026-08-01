# TokenMyBar Privacy

TokenMyBar is local-first.

## Defaults

- No TokenMyBar cloud account.
- Zero telemetry.
- Reads only known provider paths, and never writes to them.
- Provider API calls go straight to the vendor using credentials that vendor's own
  tool already stored, and only for enabled providers.
- No credential store is ever written back, modified, or repaired.

## Keychain

TokenMyBar reads Keychain items owned by *other* apps. It never writes, deletes,
or creates one — `Keychain.swift` exposes read accessors only.

Two kinds of item are read, both automatically during a refresh:

- `Claude Code-credentials` (generic password, written by Claude Code) — for the
  Claude OAuth access token.
- `<Browser> Safe Storage` (generic password, written by a Chromium browser) — the
  key needed to decrypt that browser's cookie store, and only when that browser
  actually holds an `opencode.ai` cookie.

macOS shows its own access-approval dialog the first time TokenMyBar reads another
app's item. That prompt is the consent gate, and it is never bypassed or
suppressed.

## Provider Auth

- Codex: reads `access_token` and `account_id` from `~/.codex/auth.json` (or
  `$CODEX_HOME/auth.json`).
- Claude: reads `~/.claude/.credentials.json` if present, otherwise the
  `Claude Code-credentials` Keychain item.
- OpenCode: uses `TOKEN_MY_BAR_OPENCODE_COOKIE` when set, then an `[opencode]
  cookie` value in `~/.config/token-my-bar/config.toml`; otherwise imports the
  `opencode.ai` cookie from a local browser (see below). A cookie written into
  that config file is a credential you supplied — keep the file `0600`; the app
  warns when it is readable by anyone else.
- Local cost/history scans read known provider log paths only: `~/.claude/projects`,
  `~/.codex/sessions` (override `TOKEN_MY_BAR_CODEX_HOME`), and
  `~/.local/share/opencode/opencode.db` or `$XDG_DATA_HOME/opencode/opencode.db`
  (override `TOKEN_MY_BAR_OPENCODE_DB`).

## Browser Cookies

Only for OpenCode, only the `opencode.ai` domain, and only when
`TOKEN_MY_BAR_OPENCODE_COOKIE` is unset or empty.

Cookie stores are probed in this order, stopping at the first browser that has a
matching cookie:

1. Arc, Google Chrome, Brave, Microsoft Edge, Chromium, Vivaldi — each profile's
   `Cookies` / `Network/Cookies` SQLite store under
   `~/Library/Application Support/<browser>`.
2. Firefox — `~/Library/Application Support/Firefox/Profiles/*/cookies.sqlite`
   (values are plaintext there, so no Keychain read happens).

For a Chromium browser the store is queried *before* the Keychain: only if a row
for `opencode.ai` exists does TokenMyBar read that browser's Safe Storage key to
decrypt it. Browsers you never signed into never trigger a prompt.

Live stores stay locked while the browser runs, so the database (plus its `-wal` /
`-shm` sidecars) is copied into a `0700` temp directory, read there, and deleted
when the read finishes. Only rows whose host is `opencode.ai` or a subdomain of
it, and that have not expired, are used.

## Full Disk Access

TokenMyBar does not ask for blanket Full Disk Access.

Flow:

1. Probe known provider paths.
2. If a read fails, that vendor's card shows the provider's own failure message.
3. User decides next action.

## Diagnostics

Diagnostics carry no secrets by construction rather than by scrubbing:

- Unified logging (`app.tokenmybar` subsystem) records only provider ids,
  statuses, vendor counts, and HTTP codes.
- `token-my-bar status --verbose` prints display names, statuses, auth *labels*
  (e.g. "Codex OAuth"), and usage rows. `token-my-bar doctor` prints the OS
  version, the cache path, and the vendor list.
- Tokens, cookies, authorization headers, API keys, and passwords are never
  logged, printed, or exported. Any future support export must also redact email
  addresses and local paths.

## Cache

Provider data leaves memory in two places, both under the cache directory: the
snapshot cache and the local-log scan cache. (The only other things TokenMyBar
writes are its own UI preferences via `UserDefaults`, the `snapshots.json.lock`
sibling, and the throwaway cookie-store copies described above.)

```text
~/Library/Application Support/token-my-bar/cache/snapshots.json
~/Library/Application Support/token-my-bar/cache/local-scan-<vendor>.json
```

The scan cache exists so the local-log fallback does not re-parse every JSONL file
on every refresh. Per log file it stores the path, size, modification date, the
token totals that file contributed, and the message ids already counted — the ids
are needed to keep a message that appears in two files from being counted twice.
It holds no prompts, no completions, no credentials; deleting it only costs one
slower scan. Same permissions and atomic-write rules as the snapshot cache below.

Its directory is created `0700` and the file `0600`; writes are atomic (temp file
plus rename), and a `snapshots.json.lock` sibling holds the advisory `flock` that
keeps concurrent refreshes single-flight.

It contains one JSON record per vendor: provider id and display name, status,
observed token counts and limit, unit, usage percent, window name, reset and
refresh timestamps, which sources were used, confidence, an estimated flag, a
human-readable message, an auth *label* such as "Claude OAuth", the plan name, and
the per-window usage rows.

It contains no OAuth tokens, no cookies, no authorization headers, no API keys, no
passwords, and no filesystem paths.

## Config

Read-only — TokenMyBar never writes it:

```text
$XDG_CONFIG_HOME/token-my-bar/config.toml
~/.config/token-my-bar/config.toml
```
