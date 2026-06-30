# Contributing to TokenMyBar

Thanks for your interest in contributing. This guide covers the repo layout, how
to build and test, and the conventions we follow.

## Repository Layout

TokenMyBar is a pnpm monorepo (`pnpm-workspace.yaml` globs `packages/*`):

- `packages/menubar` — the native macOS menu bar app, shared Swift core, and
  Swift CLI, built with SwiftPM (`Package.swift`).
  - `Sources/TokenMyBar` — AppKit/SwiftUI menu bar app.
  - `Sources/TokenMyBarCore` — provider models, refresh/cache, and parsers.
  - `Sources/TokenMyBarCLI` — the `token-my-bar` Swift CLI binary.
  - `Tests/TokenMyBarCoreTests` — `swift-testing` unit tests.
- `packages/www` — the static landing site (React + Vite + Tailwind).
- `docs/` — architecture, product spec, provider, and user docs.

## Prerequisites

- Swift 6 toolchain (Xcode 16 / current Xcode command line tools). The package
  pins `swift-tools-version: 6.0` and targets macOS 14+.
- Node.js with pnpm 11 (the repo pins `pnpm@11.1.2` via `packageManager`).

Install JavaScript dependencies once with `pnpm install`.

## Building

From the repo root:

```bash
pnpm build                                   # builds www + menubar
pnpm build:www                               # website only
swift build --package-path packages/menubar  # menubar only
```

`pnpm build:menubar` is an alias for the `swift build` command above.

## Testing

```bash
pnpm test                                     # www + menubar
pnpm test:www                                 # website only
swift test --package-path packages/menubar    # menubar only
```

`pnpm test:menubar` is an alias for the `swift test` command above.

## Code Style

- Match the style of the surrounding code in each package.
- The Swift targets build with the `StrictConcurrency` upcoming feature enabled,
  so keep types `Sendable` where required and avoid data races. Existing
  provider code is a good reference for the expected patterns.
- The website follows the existing TypeScript/React conventions; `pnpm test`
  type-checks it with `tsc`.

## Commit Conventions

This repo uses [Conventional Commits](https://www.conventionalcommits.org/).
Recent history shows the expected shape:

```
feat(menubar): rebuild popover to native spec + intrinsic sizing
fix(codex): show usage as percent used, not remaining
refactor(menubar): compact native popover layout + native header buttons
```

Use a `type(scope): summary` subject — common types are `feat`, `fix`, and
`refactor`; common scopes are `menubar`, `codex`, and `www`.

## Pull Requests

1. Branch off `main`.
2. Make focused changes; keep unrelated edits out of the PR.
3. Ensure `pnpm build` and `pnpm test` pass locally before opening the PR.
4. Write a clear PR description explaining the change and any user-facing impact.
5. Use a Conventional Commit style for the PR title.
