---
summary: "Antigravity vendor: per-model quota from the Google Code Assist endpoint, reported as fraction remaining."
read_when:
  - Debugging Antigravity usage parsing
  - Updating the Antigravity quota endpoint or credential resolution
  - Reviewing the remaining-vs-used inversion or the plan-tier call
---

# Antigravity provider

Google Antigravity usage comes from the same Code Assist quota endpoint the
Antigravity client itself calls, using the OAuth session the Antigravity /
Gemini sign-in already stored on the Mac. One official path, and — unlike the
other three vendors — no local fallback.

## Auth (credential resolution order)

1. `TOKEN_MY_BAR_GEMINI_CREDS` env var: a full path to the credential file, used
   when set and non-empty. The menu bar app is launched by Launch Services and
   inherits no shell environment, so this one reaches the CLI only.
2. `~/.gemini/oauth_creds.json`, written by the Antigravity / Gemini sign-in.

The access token is read from `access_token` / `accessToken`, the expiry from
`expiry_date` / `expiryDate` / `expires_at` — Google writes that in milliseconds
since the epoch, so values above 10^10 are divided by 1000. A file with no token
throws `AuthError.missingCredentials`. TokenMyBar never writes, refreshes, or
repairs the file.

**The token is short-lived and TokenMyBar does not refresh it.** Once the stored
expiry is in the past the snapshot carries "Antigravity sign-in expired — open
Antigravity once to renew". Saying so before the call starts failing is the
difference between one command and a dead vendor.

## Official usage

- `POST https://daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota`.
- Body: `{}`. Headers: `Authorization: Bearer …`, `Content-Type: application/json`
  (plus the `Accept: application/json` and 15s timeout every
  `RemoteJSON.request` carries).
- Response shape (recorded from the live payload): a `buckets` array, one entry
  per model.
  - `modelId` / `model_id` — required; a bucket without one is dropped.
  - `tokenType` — e.g. `REQUESTS`; lowercased into the row subtitle.
  - `resetTime` — ISO-8601, read via `RemoteJSON.resetDate`.
  - `remainingFraction` / `remaining_fraction` — 0...1 of quota **left**.

## `remainingFraction` is remaining, not used

This is the subtlety to get right. Every other vendor here reports percent
*used* on a 0–100 scale. Antigravity reports the fraction *left* on a 0...1
scale — inverted **and** differently scaled. `usedPercent` converts once, at the
edge, so nothing downstream has to know:

```swift
min(max((1 - remaining) * 100, 0), 100)
```

- `remainingFraction: 1` → **0% used**: untouched quota. The vendor's own screen
  shows that same bucket as "100% remaining".
- `remainingFraction: 0.25` → 75% used.
- `remainingFraction: 0` → 100% used: exhausted.
- Missing or non-finite (`nan`/`inf`) → `nil`, rendered `—`. Never `0`: reporting
  an unreadable field as "0% used" tells the user they have a full tank when they
  may have none.

Do not route this field through `RemoteJSON.percent`. That reader accepts only
key names that state their direction, so it does not read `remainingFraction` at
all — and it deliberately does no fraction scaling, so renaming the key into one
it does accept would report `0.25` as 0.25% used rather than 75%. Inverting a
used-percent field was a real Codex bug once (see [codex.md](codex.md));
mistaking this remaining-fraction for one is the same bug from the other side.

## Usage mapping

- One `UsageRow` per bucket: key `model-<modelId>`, title humanized from the id
  (`gemini-2.5-flash-lite` → "Gemini 2.5 Flash Lite"), subtitle the lowercased
  `tokenType`, icon `cpu`, unit `requests`.
- Rows are sorted **worst first** by percent used, so the model closest to its
  cap leads the popover. A row with no readable percent sorts last (it compares
  as `-1`); ties fall back to the row key, descending.
- Headline `usagePercent` is the **worst** bucket, so a single exhausted model is
  visible without expanding the section.
- Snapshot `resetAt` is the **earliest** row reset. `windowName` stays `unknown`
  — the endpoint names no window, it just dates each bucket.
- No buckets → status `noData` with "Antigravity reported no quota buckets",
  rather than a confident 0%.
- The snapshot reports `unit: .requests`, `primarySource: .oauth`,
  `sources: [.oauth, .api]`, `confidence: .high`, `isEstimated: false`, and no
  `usedTokens` — this endpoint counts requests, not tokens.

## Plan badge

The quota response carries no tier, so the badge costs a second call:

- `POST https://daily-cloudcode-pa.googleapis.com/v1internal:loadCodeAssist`,
  body `{"metadata":{"pluginType":"GEMINI"}}`, same bearer token.
- In `allowedTiers`, the entry with `isDefault: true` wins (else the first). Its
  `id` has `-tier` stripped and is title-cased: `standard-tier` → "Standard".
  The full `name` ("Gemini Code Assist") is used only when an entry has no `id` —
  it is too long for a badge sitting beside the vendor name.
- Best-effort by design (`try?`): a failed tier call must never fail a refresh
  that already has the numbers. It then falls back to a `tier` / `tierId` /
  `tier_id` / `plan` / `currentTier` key in the quota response, and finally to no
  badge at all.

## No local fallback

Antigravity is registered bare in `ProviderRegistry.defaultProviders()` — not
wrapped in `FallbackProvider` like Codex, Claude, and OpenCode. It keeps no
per-request usage file this app can read, so the quota endpoint is the only
source; when it fails there is nothing behind it but the last-good snapshot
cache.

## Key files

- Provider: `Sources/TokenMyBarCore/Vendors/Antigravity/AntigravityUsageProvider.swift`
- JSON parsing helpers: `Sources/TokenMyBarCore/Vendors/Support/RemoteJSON.swift`
- Registration: `Sources/TokenMyBarCore/ProviderClient.swift`
- Error mapping: `Sources/TokenMyBarCore/Vendors/Support/ProviderSnapshot+Failure.swift`
- Live payload shapes: `Tests/TokenMyBarCoreTests/AntigravityUsageProviderTests.swift`

## Troubleshooting

- **Vendor shows `Sign in`** — no credential file, or it holds no access token
  ("Antigravity credentials not found — sign in to Antigravity once"). Sign in to
  Antigravity once, then refresh. A rejected token (HTTP 401/403) reaches the
  same `unauthenticated` state via `.failure(...)`, worded "Authentication
  expired — sign in again"; any other HTTP status becomes an `error` reading
  "Antigravity usage failed (HTTP <status>)".
- **"Antigravity sign-in expired"** — the stored token lapsed. Open Antigravity
  once so it rewrites `~/.gemini/oauth_creds.json`; TokenMyBar will not renew it
  for you.
- **Every model reads 0%** — that is what an untouched quota looks like
  (`remainingFraction: 1`), not a parse failure. Suspect a genuine bug only if
  the vendor's own screen disagrees, i.e. shows something other than "100%
  remaining".
- **Rows read `—`** — the bucket carried no readable `remainingFraction`. The
  field was renamed or arrived non-finite; check the live payload before
  trusting any number.
- **No rows at all** ("reported no quota buckets") — the account has no quota
  buckets on this endpoint, or the response shape changed.
- **Numbers fine, no plan badge** — `loadCodeAssist` failed or the account
  exposes no default tier. Expected degradation, not an error.

## Not implemented (future)

Token refresh (the app reads the stored access token and reports when it has
lapsed), a local usage-log fallback, and per-model quota history are not
implemented.
