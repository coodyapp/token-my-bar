# token-my-bar

TokenMyBar does one thing perfectly: it turns your live AI token usage into a single, glanceable application right in your Mac's menu bar.

## Packages

- `packages/menubar`: Swift macOS menu bar app, shared core, and Swift CLI.
- `packages/www`: React + Vite website.
- Swift CLI lives in `packages/menubar/Sources/TokenMyBarCLI`.

## Development

```bash
swift build --package-path packages/menubar
swift test --package-path packages/menubar
pnpm install
pnpm build:www
```
