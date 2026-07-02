# TokenMyBar Menubar Scripts

## `package.sh`

Builds `TokenMyBar.app` and a `.dmg` from the SwiftPM executable into `dist/`.

```bash
Scripts/package.sh [version]   # version defaults to latest git tag, else 0.0.0-dev
```

Signing and notarization are opt-in via environment variables — unset, you get
an unsigned local build:

| Step | Env vars |
|------|----------|
| Codesign (Developer ID + hardened runtime) | `DEVELOPER_ID_APP` |
| Notarize + staple the DMG | `AC_APPLE_ID`, `AC_TEAM_ID`, `AC_PASSWORD` |

The hardened-runtime entitlements live in `TokenMyBar.entitlements` (not
sandboxed — the app reads existing local credentials the sandbox would block).

## Not yet implemented

- Sparkle appcast generation for auto-updates.
