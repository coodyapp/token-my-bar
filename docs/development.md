# Developing TokenMyBar

Monorepo layout:

| Path | What |
|---|---|
| `packages/menubar` | Swift package: menu bar app (`TokenMyBar`), shared core (`TokenMyBarCore`), CLI (`token-my-bar`) |
| `packages/www` | React + Vite marketing site |
| `docs/` | Product, architecture, vendor, and user docs |

## Prerequisites

- macOS 14+, Xcode command line tools (Swift 5.9+)
- Node 20 + pnpm (only for `packages/www`)

## Build & test

```bash
# Swift app + core + CLI
swift build --package-path packages/menubar
swift test  --package-path packages/menubar

# Run the app from the build tree
swift run --package-path packages/menubar TokenMyBar

# Diagnostics CLI
swift run --package-path packages/menubar token-my-bar status --refresh --verbose

# Website
pnpm install
pnpm test:www && pnpm build:www
```

`pnpm test` runs both suites.

## Architecture

Read [architecture.md](architecture.md) first. Short version: each vendor
implements `ProviderClient` and returns a `ProviderSnapshot`; `FallbackProvider`
pairs an official (OAuth/cookie) provider with a local-history fallback;
`UsageRefresher` fans out with timeouts and merges through `SnapshotMerger` into
a disk cache (`SnapshotStore`). The SwiftUI layer renders whatever snapshots say.

To add a vendor, follow [adding-a-provider.md](adding-a-provider.md).

### Hard-won provider rules

- **Never guess API payload shapes.** Fetch the live payload with local
  credentials and encode the real shape in tests
  (`OfficialUsageProviderTests`). Two production bugs came from assumed
  semantics (Codex `used_percent` was inverted as if it were "remaining").
- All vendors report percent **used** on a 0–100 scale. `RemoteJSON.percent`
  never fraction-scales.
- Prefer absolute reset timestamps (`reset_at`) over countdown/window-length
  fields when both exist.
- macOS rejects `SecItemCopyMatching` with `kSecMatchLimitAll` +
  `kSecReturnData`; enumerate attributes, then fetch secrets per item
  (see `Keychain.genericPasswords`).

## CI/CD

- `.github/workflows/ci.yml` — build + test (Swift on macOS, www on Linux) for
  every push/PR to `main`.
- `.github/workflows/release.yml` — on a `v*` tag: run tests, build the app
  bundle and DMG via `packages/menubar/Scripts/package.sh`, and create a GitHub
  release with the DMG attached.

## Cutting a release

1. Update `CHANGELOG.md` (move Unreleased → new version section).
2. Commit, push `main`, wait for CI green.
3. `git tag vX.Y.Z && git push origin vX.Y.Z` — the release workflow does the rest.
4. Update `Casks/token-my-bar.rb` with the new version and the `sha256` of the
   **released** DMG (`shasum -a 256 TokenMyBar-X.Y.Z.dmg`), commit and push.

Signing/notarization are opt-in in `package.sh` via `DEVELOPER_ID_APP` /
`AC_APPLE_ID` / `AC_TEAM_ID` / `AC_PASSWORD` (see the script header). Releases
are unsigned until those secrets are configured.
