# v1.0.0 Release Plan

## Verification
- [ ] Full test suite in release configuration (`swift test -c release`)
- [ ] www tests + build (`pnpm test:www`, `pnpm build:www`)
- [ ] `package.sh 1.0.0` → .app + .dmg build succeeds
- [ ] Smoke-test packaged .app (launches, menu bar appears)
- [ ] Release viability check (version strings, docs accuracy, known gaps)

## Docs
- [ ] Re-check existing docs/ for accuracy after recent fixes (plan badges, Codex percent, Keychain)
- [ ] docs/installation.md (end-user: dmg + brew)
- [ ] docs/development.md (developer: build, test, release process)
- [ ] README refresh (install instructions, badges)
- [ ] CHANGELOG.md (v1.0.0)

## CI/CD
- [ ] Keep ci.yml (verify it covers release build)
- [ ] .github/workflows/release.yml: on tag v* → test, package, GitHub release + dmg asset

## Distribution
- [ ] Casks/token-my-bar.rb (brew cask; note: private repo limits anonymous brew)
- [ ] Enable GitHub wiki, push Home/Installation/Troubleshooting/Development pages

## Ship
- [ ] Commit + push main
- [ ] Tag v1.0.0, push tag, watch release workflow
- [ ] Verify release assets; update cask sha256 from released dmg
- [ ] Review section below

## Review
(to fill after completion)
