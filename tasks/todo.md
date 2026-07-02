# Rebuild apps/www from tmp/ template

Template: tmp/ = SAK single-page Vite+React+Tailwind v4+shadcn site (ASCII logo, install cmd + copy toast, usage block, footer). Recreate apps/www with same structure, TokenMyBar context. Keep MenubarPreview component.

## Tasks

- [x] Copy tmp config skeleton: components.json, eslint.config.js, .prettierrc, .prettierignore, .gitignore, tsconfig trio
- [x] vite.config.ts: version single-source from Casks/token-my-bar.rb → VITE_TMB_VERSION
- [x] package.json: keep name/scripts contract (CI runs test/build), add sonner, radix-ui, eslint+prettier stack
- [x] index.html: TokenMyBar title/meta
- [x] src/index.css, theme-provider, ui/button, ui/sonner, lib/utils from tmp
- [x] src/App.tsx: TMB ASCII logo, brew install + copy toast, MenubarPreview, supported note, footer
- [x] src/components/menubar-preview.tsx: keep (moved out of site/), keep ui/badge.tsx
- [x] Delete old: site/*, theme-toggle, ui/card, vite-env.d.ts, tsconfig.tsbuildinfo
- [x] pnpm install, run dev server, verify serving (browser extension unavailable — verified via module transforms + bundle grep)
- [x] tsc build green (pnpm test:www), eslint green, vite build green

## Review

- apps/www now mirrors tmp/ exactly: same config skeleton, single-file App.tsx page (ASCII logo → tagline → install cmd + copy toast → preview → support note → footer), tmp theme (red oklch primary, Geist, animate-logo).
- Deviations from tmp: kept MenubarPreview + ui/badge.tsx (user asked to keep menubar app image); version read from Casks/token-my-bar.rb instead of cli bin; TokenMyBar meta/copy.
- Fix needed: eslint-plugin-react-hooks 6.1.1 exposes `configs.recommended` not `configs.flat.recommended` (tmp's config crashed eslint).
- CI/CD contract preserved: package name @token-my-bar/www, dev/build/test scripts unchanged; cd.yaml deploys dist/ as before.
- Verification: pnpm test:www ✅, lint ✅, build:www ✅, dev server :5173 serving all modules 200, bundle contains brew cmd + v1.0.1 + preview strings. Visual check skipped — Chrome extension not connected.
