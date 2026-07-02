# Development

```bash
swift build --package-path packages/menubar
swift test  --package-path packages/menubar   # 82 tests
pnpm install && pnpm test:www
```

- Architecture: [docs/architecture.md](https://github.com/coodyapp/token-my-bar/blob/main/docs/architecture.md)
- Adding a vendor: [docs/adding-a-provider.md](https://github.com/coodyapp/token-my-bar/blob/main/docs/adding-a-provider.md)
- Full dev guide + release process: [docs/development.md](https://github.com/coodyapp/token-my-bar/blob/main/docs/development.md)

Golden rule: never guess vendor API payload shapes — fetch the live payload and encode it in tests.
