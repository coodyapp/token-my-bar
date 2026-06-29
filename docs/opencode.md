---
summary: "OpenCode vendor: cookie auth (env + browser import) and workspace usage parsing."
read_when:
  - Adding or modifying the OpenCode provider
  - Debugging OpenCode usage parsing or browser cookie import
---

# OpenCode provider

OpenCode usage comes from the authenticated `opencode.ai` web session. There is
no public OAuth API, so TokenMyBar reuses the `opencode.ai` `auth` cookie.

## Auth (cookie resolution order)

1. `TOKEN_MY_BAR_OPENCODE_COOKIE` env var (raw value or a full `Cookie:` header).
2. Browser import (`BrowserCookieImporter`), domain `opencode.ai`:
   - Chromium family (Arc, Chrome, Brave, Edge, Chromium, Vivaldi): reads the
     `auth` cookie from `<user data>/<profile>/Cookies` (or `.../Network/Cookies`),
     decrypts the `v10` AES-128-CBC blob using the browser's "<Browser> Safe
     Storage" Keychain key (PBKDF2-HMAC-SHA1, salt `saltysalt`, 1003 rounds), and
     strips the 32-byte SHA-256 domain prefix added by modern Chromium.
   - Firefox: reads the plaintext `value` from `Profiles/*/cookies.sqlite`.
   - A browser's Safe Storage Keychain key is only read when that browser
     actually holds an `opencode.ai` cookie, so users are not prompted for
     browsers they never signed into.

Cookie databases are copied to a temp file before reading because browsers keep
the live store locked.

## Usage flow

1. **Workspace IDs**: `GET https://opencode.ai/_server?id=<workspacesFnID>` with
   headers `X-Server-Id`, `X-Server-Instance: server-fn:<uuid>`, `Origin`,
   `Referer`, `User-Agent`. `workspacesFnID =
   def39973159c7f0483d8793a822b8dbb10d067e12c65455fcb4608459ba0234f`.
   All `wrk_…` IDs are extracted from the serialized JS response, in order.
2. **Usage**: `GET https://opencode.ai/workspace/<wrk_…>/go` (HTML page). The
   first workspace that reports usage windows wins. `TOKEN_MY_BAR_OPENCODE_WORKSPACE_ID`
   (raw `wrk_…` or full URL) skips the lookup.

## Usage mapping

The workspace page embeds serialized JS objects, parsed by regex:

- Rolling 5-hour window → `rollingUsage` (`usagePercent`, `resetInSec`).
- Weekly window → `weeklyUsage`.
- Monthly window → `monthlyUsage`.

Each window becomes a `UsageRow` titled "Rolling Usage" / "Weekly Usage" /
"Monthly Usage". `resetAt = now + resetInSec`. A decoy `monthlyUsage:0,` token in
the page is ignored because parsing only matches `key…={ … }` object
assignments.

## Notes

- Responses are `text/javascript`, not JSON; fields are extracted with bounded
  regexes (`usagePercent` may appear after `resetInSec`).
- Missing usage windows raise a parse error and the provider falls back to the
  local OpenCode SQLite history (`~/.local/share/opencode/opencode.db` or
  `$XDG_DATA_HOME/opencode/opencode.db`, override `TOKEN_MY_BAR_OPENCODE_DB`).

## Key files

- Cookie auth + browser import: `Sources/TokenMyBarCore/Providers/Support/Keychain.swift`,
  `Sources/TokenMyBarCore/Providers/Support/ChromiumCookieDecryptor.swift`,
  `Sources/TokenMyBarCore/Providers/OpenCode/BrowserCookieImporter.swift`
- Provider + parsing: `Sources/TokenMyBarCore/Providers/OpenCode/OpenCodeCookieUsageProvider.swift`
- Local fallback: `Sources/TokenMyBarCore/OpenCodeLocalUsageProvider.swift`
