# v1.0.0 Release Plan

## Verification
- [x] Full test suite in release configuration (82/82, `swift test -c release`)
- [x] www tests + build (tsc clean, vite build OK)
- [x] `package.sh 1.0.0` → .app + .dmg build succeeds
- [x] Smoke-test packaged .app (launches, process up)
- [x] Release viability check (UA bumped to 1.0; version comes from tag)

## Docs
- [x] Re-checked existing docs/ (accurate post-fixes; plan badges added to user-guide)
- [x] docs/installation.md (DMG + brew + source + first-run Keychain)
- [x] docs/development.md (layout, provider rules, CI/CD, release process)
- [x] README refresh (install section, doc links)
- [x] CHANGELOG.md (1.0.0)

## CI/CD
- [x] ci.yml verified — was broken (pnpm 11 needs Node ≥22.13); fixed Node 20→22, now green
- [x] release.yml: tag → release-config tests → package.sh → GitHub release + DMG + sha256

## Distribution
- [x] Casks/token-my-bar.rb, sha256 pinned to released DMG (verified by re-download)
- [x] Wiki: **blocked** — GitHub disallows wikis on private free-plan repos
      (PATCH has_wiki stays false). Pages staged in `wiki/` with publish
      instructions for when the repo goes public.

## Ship
- [x] Commits pushed to main (1f454a2, 020ee2c, eddac3d)
- [x] Tag v1.0.0 pushed; release workflow succeeded first try
- [x] Release verified: DMG mounts, bundle version 1.0.0, checksum matches cask
- [x] CI green on main (Swift + Web)

## Review

Shipped v1.0.0: https://github.com/coodyapp/token-my-bar/releases/tag/v1.0.0

Notable decisions:
- CD builds the canonical DMG (runner build ≠ local build), so the cask sha256
  is taken from the released asset, not the local package.
- Releases are unsigned/not notarized until DEVELOPER_ID_APP / AC_* secrets
  exist; documented Gatekeeper workaround in installation.md and cask caveats.
- Brew from a private repo needs authenticated git/HOMEBREW_GITHUB_API_TOKEN;
  documented. Public repo removes the caveat.

Lessons:
- GitHub wiki is a plan feature: private + free ⇒ has_wiki silently stays false.
- pnpm 11 requires Node ≥ 22.13 — setup-node must track pnpm's engine floor.
- Don't exec a menu bar app binary with --help; AppKit apps ignore argv and
  block forever.
