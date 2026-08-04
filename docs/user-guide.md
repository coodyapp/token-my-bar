# TokenMyBar User Guide

TokenMyBar is a native macOS menu bar app that shows AI usage from OpenCode, OpenAI Codex, Claude Code, and Google Antigravity.

## Requirements

- macOS 14 or newer
- Existing OpenCode, Codex, Claude Code, or Antigravity sessions on this Mac

## Menu Bar Display

Open Settings from the popover menu and choose `Display Mode`:

- `Icon + Percentage`: native vendor icon followed by usage percentage.
- `Percentage Only`: usage percentages without icons.
- `Icons Only`: compact vendor icons without labels.
- `Summary`: one calculated percentage.
- `Custom`: currently follows icon plus percentage while preserving future custom behavior.

## Plan Badges

Each vendor section shows your subscription plan next to the vendor name when
it can be determined: Claude Code (e.g. `Pro`, `Max 5x`), OpenAI Codex
(e.g. `Plus`), OpenCode (`Go`), and Antigravity (e.g. `Pro`). While Antigravity
runs, its badge arrives with the usage reading; on the OAuth fallback it comes
from a separate best-effort call, so usage can be correct while the badge is
missing.

## Vendors

Use `Vendors` to enable or disable:

- OpenCode
- Codex
- Claude
- Antigravity

Disabled vendors are skipped during refresh and hidden from the menu bar.

Antigravity shows one grouped `Gemini models` row — all Gemini models share
that allowance, and it is the same figure Antigravity's own quota screen shows.
Per-model rows, ordered worst first, appear only when Antigravity is closed and
the OAuth fallback answers instead. A row at 0% has an untouched quota;
Antigravity's own screen calls the same thing "100% remaining".

## Summary Calculation

Summary mode can calculate:

- `Highest Usage`: shows the vendor with the highest known usage percent.
- `Average Usage`: shows average percent across active vendors.
- `Selected Provider`: uses the configured primary vendor when available.

## Menu Bar Behavior

- `Hide labels when space is limited`: reserved for compact menu bar behavior.
- `Collapse to summary automatically`: switches to summary when multiple vendors would take too much space.
- `Show provider order`: keeps selected primary vendor first when configured.
- `Show colored usage indicators`: lets menu bar text use accent color when monochrome is disabled.
- `Monochrome icons`: follows macOS menu bar style.

## Refresh

- Click the refresh icon in the popover.
- Use `Command-R` while the popover is focused.
- Right-click the menu bar item and choose `Refresh`.

## Configuration File

A few settings live in a text file instead of the Settings window, including the
overrides that keep OpenCode working when `opencode.ai` changes. Create
`~/.config/token-my-bar/config.toml` (or
`$XDG_CONFIG_HOME/token-my-bar/config.toml`). It is re-read on every refresh, so
no relaunch is needed.

```ini
[ui]
primary = codex             # codex, claude, opencode, or antigravity

[refresh]
ttl_seconds = 120

[opencode]
cookie = "auth=abc123; other=def"
workspace_id = wrk_01ABC
db = ~/.local/share/opencode/opencode.db
```

- `ui.primary`: vendor shown first and used by `Selected Provider` summary mode.
  Accepts `codex`/`openai`, `claude`/`claude-code`/`anthropic`, `opencode`,
  `antigravity`.
- `refresh.ttl_seconds`: how long cached usage is reused before a refresh really
  fetches (default 120). A shorter refresh interval bounds it to half that
  interval.
- `opencode.cookie`: `opencode.ai` session cookie, used instead of reading it
  from your browser — the fix when TokenMyBar cannot decrypt the browser cookie
  store. Copy the `Cookie` request header for `opencode.ai` from your browser's
  developer tools; a full `Cookie: …` header or the bare `auth=…` value both work.
- `opencode.workspace_id`: the bare `wrk_…` id, skipping workspace discovery —
  the fix when `opencode.ai` changes and OpenCode reports an error. Take it from
  the `opencode.ai/workspace/<id>/go` URL; anything that is not a plain id is
  ignored and discovery runs as usual.
- `opencode.db`: path to the local OpenCode SQLite database used as fallback
  history. `~` is expanded. The app cannot see `XDG_DATA_HOME`, so this is how it
  finds a database outside `~/.local/share/opencode/opencode.db`.

Notes:

- Quote any value containing `;` — an unquoted value ends at the first `#` or
  `;`, which would cut a cookie in half.
- `opencode.cookie` is a live credential. Run
  `chmod 600 ~/.config/token-my-bar/config.toml`; TokenMyBar logs a warning
  (Console.app, subsystem `app.tokenmybar`) while the file is readable by others.
- The matching environment variables `TOKEN_MY_BAR_OPENCODE_COOKIE`,
  `TOKEN_MY_BAR_OPENCODE_WORKSPACE_ID` and `TOKEN_MY_BAR_OPENCODE_DB` override
  the file, but they only reach the `token-my-bar` CLI: the menu bar app is
  launched by macOS and inherits no shell environment, so use the file for the
  app.
- `TOKEN_MY_BAR_GEMINI_CREDS` points Antigravity at a credential file other than
  `~/.gemini/oauth_creds.json`, and `TOKEN_MY_BAR_CODEX_HOME` points Codex's
  local history scan at a directory other than `~/.codex`. Neither has a
  `config.toml` key, so — being environment variables — they reach the CLI only;
  the app always uses the default path.

## Privacy

TokenMyBar reads usage from local app sessions and provider APIs using existing local credentials. It does not proxy usage through TokenMyBar servers and does not store secrets in snapshot cache. Exactly which files, Keychain items, and browser cookie stores are read: [privacy.md](privacy.md).

## Troubleshooting

- If usage is missing, open the source app once and refresh TokenMyBar.
- If a vendor says `Sign in`, re-authenticate in that vendor's app.
- If Claude shows no data, approve the macOS Keychain prompt — choose
  **Always Allow** so it stops asking on every refresh.
- If OpenCode shows no data, sign in to `opencode.ai` in Arc, Chrome, Brave, Edge,
  Chromium, Vivaldi, or Firefox first; browser import has nothing to read until a
  session cookie exists.
- If Antigravity says `Sign in`, or shows **Antigravity sign-in expired — open
  Antigravity once to renew**, just open Antigravity and refresh: while it runs,
  usage comes straight from its language server, no token needed. Those messages
  come from the OAuth fallback used when Antigravity is closed — its access
  token is short-lived and TokenMyBar deliberately never renews it for you; it
  only reads `~/.gemini/oauth_creds.json`, which Antigravity rewrites when you
  use it. There is no usage history behind this vendor, so a closed IDE plus an
  expired sign-in leaves nothing to show but the last reading.
- If Antigravity shows a row at `0%`, that is a full quota, not an error: the
  vendor's own screen reports the same bucket as "100% remaining". A row at
  `100%` is the exhausted one.
- If Antigravity's numbers look right but the plan badge is missing, the separate
  tier lookup failed. It is best-effort and never blocks a refresh; ignore it.
- If a vendor is badged `Stale`, the official source was unreachable and the shown
  numbers are the last good reading (local history where a fallback exists).
  Refresh, or re-authenticate if it persists.
- If macOS blocks the app on first launch, see the Gatekeeper notes in
  [installation.md](installation.md) — releases are ad-hoc signed, not notarized.
- If OpenCode keeps failing after an `opencode.ai` change, set
  `[opencode] workspace_id` or `[opencode] cookie` in the configuration file
  above; both take effect on the next refresh.
- If the menu bar is crowded, enable `Collapse to summary automatically`.
- If the app shows in Activity Monitor but the menu bar icon never appears
  (stuck before startup with 0% CPU), macOS kept a stale launch record for
  the app path — this can happen after a Gatekeeper block followed by
  reinstalls. Quit the stuck process, then run once with
  `DYLD_PRINT_LIBRARIES=1 /Applications/TokenMyBar.app/Contents/MacOS/TokenMyBar`
  (or reboot); normal launches work again afterwards.
